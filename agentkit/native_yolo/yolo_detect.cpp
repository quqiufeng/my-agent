// yolo_detect.cpp — YOLO 检测（libtorch 推理 + OpenCV 画框），原生 C++
// 用法: yolo_detect <model.torchscript> <in.jpg|ppm> <out.jpg> [conf=0.35]
#include <torch/script.h>
#include <opencv2/opencv.hpp>
#include <iostream>
#include <vector>
#include <algorithm>

struct Det { float x,y,w,h,conf; int cls; };

static float iou(const Det&a, const Det&b){
  float ax1=a.x-a.w/2, ay1=a.y-a.h/2, ax2=a.x+a.w/2, ay2=a.y+a.h/2;
  float bx1=b.x-b.w/2, by1=b.y-b.h/2, bx2=b.x+b.w/2, by2=b.y+b.h/2;
  float ix=std::max(0.f,std::min(ax2,bx2)-std::max(ax1,bx1));
  float iy=std::max(0.f,std::min(ay2,by2)-std::max(ay1,by1));
  float inter=ix*iy, uni=a.w*a.h+b.w*b.h-inter;
  return uni>0?inter/uni:0;
}

int main(int argc,char**argv){
  if(argc<4){ std::cerr<<"usage: yolo_detect <model> <in> <out> [conf]\n"; return 2; }
  std::string model=argv[1], in=argv[2], out=argv[3];
  float conf_thr = argc>4?atof(argv[4]):0.35f;
  try{
    torch::jit::script::Module m = torch::jit::load(model);
    m.eval();
    cv::Mat bgr = cv::imread(in, cv::IMREAD_COLOR);
    if(bgr.empty()){ std::cerr<<"read image failed: "<<in<<"\n"; return 1; }
    int W=bgr.cols, H=bgr.rows;
    cv::Mat rgb; cv::cvtColor(bgr, rgb, cv::COLOR_BGR2RGB);
    cv::Mat rs; cv::resize(rgb, rs, cv::Size(640,640));
    torch::Tensor t = torch::from_blob(rs.data,{640,640,3},torch::kUInt8).clone();
    t = t.permute({2,0,1}).to(torch::kFloat32).div(255.0).unsqueeze(0).contiguous();
    torch::Tensor o = m.forward({t}).toTensor();     // [1,84,8400]
    o = o.squeeze(0).contiguous().to(torch::kCPU);    // [84,8400]
    auto a = o.accessor<float,2>();
    int N = o.size(1), ncls = o.size(0)-4;
    std::vector<Det> dets;
    for(int i=0;i<N;i++){
      float best=0; int bc=-1;
      for(int c=0;c<ncls;c++){ float s=a[4+c][i]; if(s>best){best=s;bc=c;} }
      if(best<conf_thr) continue;
      float cx=a[0][i], cy=a[1][i], w=a[2][i], h=a[3][i];
      Det d; d.x=cx*W/640.f; d.y=cy*H/640.f; d.w=w*W/640.f; d.h=h*H/640.f; d.conf=best; d.cls=bc;
      dets.push_back(d);
    }
    // NMS
    std::sort(dets.begin(),dets.end(),[](const Det&a,const Det&b){return a.conf>b.conf;});
    std::vector<Det> keep; std::vector<char> rm(dets.size(),0);
    for(size_t i=0;i<dets.size();i++){ if(rm[i])continue; keep.push_back(dets[i]);
      for(size_t j=i+1;j<dets.size();j++) if(!rm[j]&&dets[i].cls==dets[j].cls&&iou(dets[i],dets[j])>0.45) rm[j]=1; }
    static const char* names[]={"person","bicycle","car","motorcycle","airplane","bus","train","truck","boat","traffic light","fire hydrant","stop sign","parking meter","bench","bird","cat","dog","horse","sheep","cow","elephant","bear","zebra","giraffe","backpack","umbrella","handbag","tie","suitcase","frisbee","skis","snowboard","sports ball","kite","baseball bat","baseball glove","skateboard","surfboard","tennis racket","bottle","wine glass","cup","fork","knife","spoon","bowl","banana","apple","sandwich","orange","broccoli","carrot","hot dog","pizza","donut","cake","chair","couch","potted plant","bed","dining table","toilet","tv","laptop","mouse","remote","keyboard","cell phone","microwave","oven","toaster","sink","refrigerator","book","clock","vase","scissors","teddy bear","hair drier","toothbrush"};
    for(auto&d:keep){
      int x1=int(d.x-d.w/2), y1=int(d.y-d.h/2), x2=int(d.x+d.w/2), y2=int(d.y+d.h/2);
      x1=std::max(0,x1); y1=std::max(0,y1); x2=std::min(W-1,x2); y2=std::min(H-1,y2);
      cv::rectangle(bgr,{x1,y1},{x2,y2},cv::Scalar(0,0,255),2);
      const char* nm=(d.cls>=0&&d.cls<80)?names[d.cls]:"obj";
      char lb[64]; snprintf(lb,sizeof lb,"%s %.2f",nm,d.conf);
      cv::putText(bgr,lb,{x1,std::max(14,y1-6)},cv::FONT_HERSHEY_SIMPLEX,0.6,cv::Scalar(0,0,255),2);
      printf("%s %.3f %d %d %d %d\n", nm, d.conf, x1,y1,x2,y2);
    }
    printf("TOTAL %zu\n", keep.size());
    cv::imwrite(out, bgr);
    printf("SAVED %s\n", out.c_str());
  }catch(const std::exception&e){ std::cerr<<"err: "<<e.what()<<"\n"; return 1; }
  return 0;
}
