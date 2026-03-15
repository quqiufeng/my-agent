"""
红黑树实现
特性：
- 近似平衡的二叉搜索树
- O(log n) 时间复杂度的插入、删除、搜索操作
- 节点颜色为红色或黑色
"""

class RBNode:
    """红黑树节点"""
    def __init__(self, key, value=None, color='RED'):
        self.key = key
        self.value = value
        self.color = color  # 'RED' or 'BLACK'
        self.left = None
        self.right = None
        self.parent = None

    def __repr__(self):
        color_str = 'R' if self.color == 'RED' else 'B'
        return f"({self.key}:{self.value}|{color_str})"


class RedBlackTree:
    """
    红黑树实现
    
    性质：
    1. 每个节点要么是红色，要么是黑色
    2. 根节点必须是黑色
    3. 每个叶子节点(NIL)是黑色
    4. 红色节点的子节点必须是黑色
    5. 从任一节点到其每个叶子的所有路径都包含相同数量的黑色节点
    """
    
    def __init__(self):
        self.NIL = RBNode(key=None, color='BLACK')  # 哨兵节点
        self.NIL.left = self.NIL
        self.NIL.right = self.NIL
        self.root = self.NIL
        self.size = 0
    
    def _is_left_child(self, node):
        """判断节点是否为父节点的左子节点"""
        return node.parent and node == node.parent.left
    
    def _is_right_child(self, node):
        """判断节点是否为父节点的右子节点"""
        return node.parent and node == node.parent.right
    
    def _get_sibling(self, node):
        """获取兄弟节点"""
        if node.parent is None:
            return None
        if self._is_left_child(node):
            return node.parent.right
        return node.parent.left
    
    def _get_uncle(self, node):
        """获取叔父节点"""
        if node.parent is None:
            return None
        return self._get_sibling(node.parent)
    
    def _rotate_left(self, x):
        """左旋"""
        y = x.right
        x.right = y.left
        if y.left != self.NIL:
            y.left.parent = x
        y.parent = x.parent
        if x.parent is None:
            self.root = y
        elif self._is_left_child(x):
            x.parent.left = y
        else:
            x.parent.right = y
        y.left = x
        x.parent = y
    
    def _rotate_right(self, y):
        """右旋"""
        x = y.left
        y.left = x.right
        if x.right != self.NIL:
            x.right.parent = y
        x.parent = y.parent
        if y.parent is None:
            self.root = x
        elif self._is_right_child(y):
            y.parent.right = x
        else:
            y.parent.left = x
        x.right = y
        y.parent = x
    
    def _insert_fixup(self, node):
        """插入后修复红黑树性质"""
        while node.parent and node.parent.color == 'RED':
            uncle = self._get_uncle(node)
            
            # 情况1: 叔父节点是红色
            if uncle and uncle.color == 'RED':
                node.parent.color = 'BLACK'
                uncle.color = 'BLACK'
                node.parent.parent.color = 'RED'
                node = node.parent.parent
            else:
                # 情况2: 叔父节点是黑色，当前节点是右子节点
                if self._is_right_child(node) and self._is_left_child(node.parent):
                    node = node.parent
                    self._rotate_left(node)
                # 情况3: 叔父节点是黑色，当前节点是左子节点
                elif self._is_left_child(node) and self._is_right_child(node.parent):
                    node = node.parent
                    self._rotate_right(node)
                
                # 调整颜色并旋转
                node.parent.color = 'BLACK'
                node.parent.parent.color = 'RED'
                if node.parent.parent != self.NIL:
                    if self._is_left_child(node.parent):
                        self._rotate_right(node.parent.parent)
                    else:
                        self._rotate_left(node.parent.parent)
        
        # 确保根节点是黑色
        self.root.color = 'BLACK'
    
    def insert(self, key, value=None):
        """插入节点"""
        # 创建新节点
        new_node = RBNode(key, value, 'RED')
        new_node.left = self.NIL
        new_node.right = self.NIL
        new_node.parent = None
        
        # 查找插入位置
        parent = None
        current = self.root
        
        while current != self.NIL:
            parent = current
            if key < current.key:
                current = current.left
            elif key > current.key:
                current = current.right
            else:
                # 键已存在，更新值
                current.value = value
                return
        
        # 插入新节点
        new_node.parent = parent
        if parent is None:
            self.root = new_node
        elif key < parent.key:
            parent.left = new_node
        else:
            parent.right = new_node
        
        self.size += 1
        
        # 修复红黑树性质
        self._insert_fixup(new_node)
    
    def _transplant(self, u, v):
        """用节点v替换节点u"""
        if u.parent is None:
            self.root = v
        elif self._is_left_child(u):
            u.parent.left = v
        else:
            u.parent.right = v
        v.parent = u.parent
    
    def _minimum(self, node):
        """找到以node为根的子树的最小节点"""
        while node.left != self.NIL:
            node = node.left
        return node
    
    def _delete_fixup(self, node):
        """删除后修复红黑树性质"""
        while node != self.root and node.color == 'BLACK':
            sibling = self._get_sibling(node)
            
            # 兄弟节点是红色
            if sibling and sibling.color == 'RED':
                sibling.color = 'BLACK'
                node.parent.color = 'RED'
                if self._is_left_child(node):
                    self._rotate_left(node.parent)
                else:
                    self._rotate_right(node.parent)
                sibling = self._get_sibling(node)
            
            # 兄弟节点是黑色，两个侄子节点都是黑色
            if sibling and sibling.left.color == 'BLACK' and sibling.right.color == 'BLACK':
                sibling.color = 'RED'
                node = node.parent
            else:
                # 兄弟节点是黑色，至少一个侄子节点是红色
                if self._is_left_child(node) and sibling and sibling.right.color == 'BLACK':
                    sibling.left.color = 'BLACK'
                    sibling.color = 'RED'
                    self._rotate_right(sibling)
                    sibling = self._get_sibling(node)
                elif self._is_right_child(node) and sibling and sibling.left.color == 'BLACK':
                    sibling.right.color = 'BLACK'
                    sibling.color = 'RED'
                    self._rotate_left(sibling)
                    sibling = self._get_sibling(node)
                
                # 当前节点是左子节点
                if sibling:
                    sibling.color = node.parent.color
                    node.parent.color = 'BLACK'
                    if self._is_left_child(node):
                        sibling.right.color = 'BLACK'
                        self._rotate_left(node.parent)
                    else:
                        sibling.left.color = 'BLACK'
                        self._rotate_right(node.parent)
            
            node = self.root
        
        node.color = 'BLACK'
    
    def _delete_node(self, node):
        """删除指定节点"""
        y = node
        y_original_color = y.color
        
        if node.left == self.NIL:
            x = node.right
            self._transplant(node, node.right)
        elif node.right == self.NIL:
            x = node.left
            self._transplant(node, node.left)
        else:
            y = self._minimum(node.right)
            y_original_color = y.color
            x = y.right
            
            if y.parent == node:
                x.parent = y
            else:
                self._transplant(y, y.right)
                y.right = node.right
                y.right.parent = y
            
            self._transplant(node, y)
            y.left = node.left
            y.left.parent = y
            y.color = node.color
        
        if y_original_color == 'BLACK':
            self._delete_fixup(x)
        
        self.size -= 1
    
    def delete(self, key):
        """删除键为key的节点"""
        node = self.search(key)
        if node != self.NIL:
            self._delete_node(node)
            return True
        return False
    
    def search(self, key):
        """搜索键为key的节点"""
        current = self.root
        while current != self.NIL:
            if key == current.key:
                return current
            elif key < current.key:
                current = current.left
            else:
                current = current.right
        return self.NIL
    
    def contains(self, key):
        """检查键是否存在"""
        return self.search(key) != self.NIL
    
    def get(self, key):
        """获取键对应的值"""
        node = self.search(key)
        return node.value if node != self.NIL else None
    
    def _inorder_helper(self, node, result):
        """中序遍历辅助函数"""
        if node != self.NIL:
            self._inorder_helper(node.left, result)
            result.append(node)
            self._inorder_helper(node.right, result)
    
    def inorder(self):
        """中序遍历返回所有节点"""
        result = []
        self._inorder_helper(self.root, result)
        return result
    
    def _preorder_helper(self, node, result):
        """先序遍历辅助函数"""
        if node != self.NIL:
            result.append(node)
            self._preorder_helper(node.left, result)
            self._preorder_helper(node.right, result)
    
    def preorder(self):
        """先序遍历返回所有节点"""
        result = []
        self._preorder_helper(self.root, result)
        return result
    
    def _postorder_helper(self, node, result):
        """后序遍历辅助函数"""
        if node != self.NIL:
            self._postorder_helper(node.left, result)
            self._postorder_helper(node.right, result)
            result.append(node)
    
    def postorder(self):
        """后序遍历返回所有节点"""
        result = []
        self._postorder_helper(self.root, result)
        return result
    
    def __len__(self):
        return self.size
    
    def __contains__(self, key):
        return self.contains(key)
    
    def __iter__(self):
        """迭代器 - 中序遍历"""
        for node in self.inorder():
            yield node.key, node.value
    
    def height(self):
        """计算树的高度"""
        def _height(node):
            if node == self.NIL:
                return -1
            return 1 + max(_height(node.left), _height(node.right))
        return _height(self.root)
    
    def min(self):
        """获取最小键"""
        if self.root == self.NIL:
            return None
        node = self._minimum(self.root)
        return node.key
    
    def max(self):
        """获取最大键"""
        if self.root == self.NIL:
            return None
        node = self.root
        while node.right != self.NIL:
            node = node.right
        return node.key
    
    def _to_dict(self, node):
        """转换为字典表示"""
        if node == self.NIL:
            return None
        return {
            'key': node.key,
            'value': node.value,
            'color': node.color,
            'left': self._to_dict(node.left),
            'right': self._to_dict(node.right)
        }
    
    def to_dict(self):
        """转换为字典"""
        return self._to_dict(self.root)


def visualize_tree(tree, node=None, prefix="", is_left=True):
    """可视化打印红黑树"""
    if node is None:
        node = tree.root
    if node == tree.NIL:
        return
    
    color_indicator = "🔴" if node.color == "RED" else "⚫"
    print(f"{prefix}{'└── ' if is_left else '┌── '}{color_indicator}[{node.key}]")
    
    children = []
    if node.left != tree.NIL:
        children.append((node.left, True))
    if node.right != tree.NIL:
        children.append((node.right, False))
    
    for i, (child, is_left_child) in enumerate(children):
        new_prefix = prefix + ("    " if is_left else "│   ")
        visualize_tree(tree, child, new_prefix, is_left_child)


# 简单测试
if __name__ == "__main__":
    # 创建红黑树
    rbt = RedBlackTree()
    
    # 插入测试
    print("=== 插入测试 ===")
    test_keys = [7, 3, 18, 10, 22, 8, 11, 26]
    for key in test_keys:
        rbt.insert(key, f"value_{key}")
        print(f"插入 {key} 后树高度: {rbt.height()}")
    
    print("\n=== 树结构 ===")
    visualize_tree(rbt)
    
    print("\n=== 遍历测试 ===")
    print("中序遍历:", [n.key for n in rbt.inorder()])
    print("先序遍历:", [n.key for n in rbt.preorder()])
    
    print("\n=== 搜索测试 ===")
    print(f"搜索 10: {rbt.search(10)}")
    print(f"搜索 5: {rbt.search(5)}")
    print(f"包含 22: {22 in rbt}")
    print(f"获取 18: {rbt.get(18)}")
    
    print("\n=== 删除测试 ===")
    rbt.delete(18)
    print("删除 18 后:")
    visualize_tree(rbt)
    print("中序遍历:", [n.key for n in rbt.inorder()])
    
    print("\n=== 最小/最大值 ===")
    print(f"最小值: {rbt.min()}")
    print(f"最大值: {rbt.max()}")
    print(f"树大小: {len(rbt)}")