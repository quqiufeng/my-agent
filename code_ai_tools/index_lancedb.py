#!/usr/bin/env python3
import os
import sys
import argparse
import gc
from pathlib import Path
import time

import lancedb
import pyarrow as pa
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter
from tqdm import tqdm

CHUNK_SIZE = 1000
OVERLAP = 150
BATCH_SIZE = 10000
DB_PATH = os.path.expanduser("~/lancedb_data")

import torch

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
if DEVICE == "cuda":
    print(f"GPU 检测成功: {torch.cuda.get_device_name(0)}")
else:
    print("警告: 未检测到 CUDA，使用 CPU")


def expand_path(path_str):
    if path_str.startswith("~/"):
        return os.path.expanduser(path_str)
    return os.path.abspath(path_str)


def index_code(repo_path, project_id):
    repo_path = expand_path(repo_path)
    print(f"索引路径: {repo_path}")
    print(f"项目ID: {project_id}")
    print(f"批次大小: {BATCH_SIZE}")
    print(f"设备: {DEVICE}")

    os.makedirs(DB_PATH, exist_ok=True)
    db = lancedb.connect(DB_PATH)

    try:
        db.drop_table(project_id)
        print(f"已删除旧表: {project_id}")
    except:
        pass

    cpp_files = []
    for ext in [".cpp", ".h", ".hpp", ".cc", ".cxx", ".hxx", ".c", ".h"]:
        for f in Path(repo_path).rglob(f"*{ext}"):
            if ".git" in f.parts or "node_modules" in f.parts:
                continue
            cpp_files.append(str(f))

    print(f"找到 {len(cpp_files)} 个 C++ 文件")

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=OVERLAP,
        separators=["\n\n", "\n", ";", "}", "{", " ", ""],
    )

    all_docs = []
    for i, file_path in enumerate(cpp_files):
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
            chunks = splitter.split_text(content)
            for chunk in chunks:
                all_docs.append(
                    {
                        "text": chunk,
                        "source": os.path.relpath(file_path, repo_path),
                    }
                )
        except Exception as e:
            print(f"跳过 {file_path}: {e}")
        if (i + 1) % 50 == 0:
            print(f"已处理 {i + 1}/{len(cpp_files)} 文件...")

    total_docs = len(all_docs)
    print(f"分割后得到 {total_docs} 个文档块")

    schema = pa.schema(
        [
            ("id", pa.int64()),
            ("text", pa.string()),
            ("source", pa.string()),
            ("vector", pa.list_(pa.float32(), 512)),
        ]
    )
    table = db.create_table(project_id, schema=schema)
    print(f"表 {project_id} 已创建")

    print("加载 embedding 模型...")
    embeddings = HuggingFaceEmbeddings(
        model_name="BAAI/bge-small-zh-v1.5", model_kwargs={"device": DEVICE}
    )

    num_batches = (total_docs + BATCH_SIZE - 1) // BATCH_SIZE
    print(f"开始分批处理，共 {num_batches} 批...")

    start_time = time.time()
    for batch_idx in tqdm(range(num_batches), desc="处理批次"):
        batch_start = time.time()

        start_idx = batch_idx * BATCH_SIZE
        end_idx = min(start_idx + BATCH_SIZE, total_docs)
        batch_docs = all_docs[start_idx:end_idx]

        texts = [doc["text"] for doc in batch_docs]
        vectors = embeddings.embed_documents(texts)

        records = [
            {
                "id": start_idx + i,
                "text": batch_docs[i]["text"],
                "source": batch_docs[i]["source"],
                "vector": vectors[i],
            }
            for i in range(len(batch_docs))
        ]

        table.add(records)

        batch_time = time.time() - batch_start
        total_time = time.time() - start_time
        avg_time = total_time / (batch_idx + 1)
        remaining = avg_time * (num_batches - batch_idx - 1)

        print(
            f"批次 {batch_idx + 1}/{num_batches} 完成 ({batch_time:.1f}秒), 表记录: {table.count_rows()}, 预计剩余: {remaining / 60:.1f}分钟"
        )

        del vectors, records, texts
        gc.collect()
        if DEVICE == "cuda":
            torch.cuda.empty_cache()

    print(f"\n✓ 项目 '{project_id}' 索引完成!")
    print(f"✓ 实际存入记录数: {table.count_rows()}")
    print(f"✓ 数据保存在: {DB_PATH}/{project_id}.lance")
    print(f"✓ 总耗时: {(time.time() - start_time) / 60:.1f} 分钟")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="LanceDB 代码索引器 (GPU加速版)")
    parser.add_argument("repo_path", help="代码仓库路径")
    parser.add_argument("project_id", help="项目ID")
    args = parser.parse_args()

    index_code(args.repo_path, args.project_id)
