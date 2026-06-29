import os
import shutil
from pathlib import Path

def extract_files_to_current_folder():
    """
    将当前文件夹内所有子文件夹中的文件提取到当前文件夹中
    """
    current_dir = Path.cwd()
    print(f"当前工作目录: {current_dir}")
    
    # 统计信息
    total_files = 0
    moved_files = 0
    duplicate_files = 0
    
    # 遍历所有子文件夹
    for root, dirs, files in os.walk(current_dir):
        root_path = Path(root)
        
        # 跳过当前目录本身
        if root_path == current_dir:
            continue
            
        print(f"\n处理文件夹: {root_path}")
        
        for file in files:
            total_files += 1
            source_file = root_path / file
            target_file = current_dir / file
            
            try:
                # 如果目标文件已存在，添加序号避免覆盖
                if target_file.exists():
                    base_name = target_file.stem
                    suffix = target_file.suffix
                    counter = 1
                    
                    while target_file.exists():
                        new_name = f"{base_name}_{counter}{suffix}"
                        target_file = current_dir / new_name
                        counter += 1
                    
                    duplicate_files += 1
                    print(f"  重命名: {file} -> {target_file.name}")
                
                # 移动文件
                shutil.move(str(source_file), str(target_file))
                moved_files += 1
                print(f"  移动: {file}")
                
            except Exception as e:
                print(f"  错误: 无法移动 {file} - {e}")
    
    # 删除空文件夹
    print(f"\n正在删除空文件夹...")
    removed_dirs = 0
    
    for root, dirs, files in os.walk(current_dir, topdown=False):
        for dir_name in dirs:
            dir_path = Path(root) / dir_name
            try:
                if not any(dir_path.iterdir()):  # 检查文件夹是否为空
                    dir_path.rmdir()
                    removed_dirs += 1
                    print(f"  删除空文件夹: {dir_path}")
            except Exception as e:
                print(f"  无法删除文件夹 {dir_path} - {e}")
    
    # 输出统计结果
    print(f"\n=" * 50)
    print(f"操作完成！")
    print(f"总共发现文件: {total_files}")
    print(f"成功移动文件: {moved_files}")
    print(f"重复文件（已重命名）: {duplicate_files}")
    print(f"删除空文件夹: {removed_dirs}")
    print(f"=" * 50)


def extract_files_with_backup():
    """
    带备份功能的文件提取（可选版本）
    """
    current_dir = Path.cwd()
    backup_dir = current_dir / "backup_before_extract"
    
    # 询问是否需要备份
    response = input("是否要在操作前创建备份？(y/n): ").lower().strip()
    
    if response == 'y':
        print("正在创建备份...")
        if backup_dir.exists():
            shutil.rmtree(backup_dir)
        
        # 创建完整的目录结构备份
        for item in current_dir.iterdir():
            if item.is_dir() and item.name != "backup_before_extract":
                shutil.copytree(item, backup_dir / item.name)
        
        print(f"备份已创建在: {backup_dir}")
    
    # 执行文件提取
    extract_files_to_current_folder()


if __name__ == "__main__":
    print("文件提取脚本")
    print("此脚本将把当前文件夹内所有子文件夹中的文件移动到当前文件夹")
    print("注意：这将改变您的文件结构！")
    
    # 显示当前目录内容概览
    current_dir = Path.cwd()
    subdirs = [d for d in current_dir.iterdir() if d.is_dir()]
    
    if not subdirs:
        print("当前文件夹内没有子文件夹。")
        exit()
    
    print(f"\n发现 {len(subdirs)} 个子文件夹:")
    for subdir in subdirs[:10]:  # 只显示前10个
        print(f"  - {subdir.name}")
    if len(subdirs) > 10:
        print(f"  ... 还有 {len(subdirs) - 10} 个文件夹")
    
    # 确认操作
    response = input(f"\n确认要继续吗？(y/n): ").lower().strip()
    
    if response == 'y':
        # 选择是否使用备份版本
        backup_response = input("需要备份功能吗？(y/n): ").lower().strip()
        
        if backup_response == 'y':
            extract_files_with_backup()
        else:
            extract_files_to_current_folder()
    else:
        print("操作已取消。")