import os
import shutil
import json
import argparse
import tempfile
import zipfile

def generate_proxy_extensions(template_dir, output_dir, proxies):
    """
    Generate Chrome extensions with custom proxy settings.
    
    Args:
        template_dir (str): Path to the template extension directory
        output_dir (str): Directory to store generated extensions
        proxies (list): List of (ip, port) tuples for proxy configurations
    
    Returns:
        list: Paths to all generated extension directories
    """
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Store paths of generated extensions
    extension_paths = []
    
    # Generate an extension for each proxy
    for i, (ip, port) in enumerate(proxies, start=1):
        # Create extension directory name
        ext_dir = os.path.join(output_dir, f"proxy-extension-{i}")
        
        # Remove directory if it already exists
        if os.path.exists(ext_dir):
            shutil.rmtree(ext_dir)
        
        # Copy template directory
        shutil.copytree(template_dir, ext_dir)
        
        # Create config.json with proxy settings
        with open(os.path.join(ext_dir, "config.json"), "w") as f:
            json.dump({"ip": ip, "port": port}, f)
            
        extension_paths.append(ext_dir)
    
    return extension_paths

def create_zip_file(extension_dirs, zip_path):
    """
    Create a zip file containing all generated extensions.
    
    Args:
        extension_dirs (list): List of extension directory paths
        zip_path (str): Path to the output zip file
        
    Returns:
        str: Path to the created zip file
    """
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for ext_dir in extension_dirs:
            for root, _, files in os.walk(ext_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, os.path.dirname(ext_dir))
                    zipf.write(file_path, arcname)
    
    return zip_path

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Generate proxy Chrome extensions')
    parser.add_argument('--template', required=True, help='Template directory path')
    parser.add_argument('--output', required=True, help='Output directory for extensions')
    parser.add_argument('--proxies', required=True, help='JSON file with proxy list')
    parser.add_argument('--zip', help='Output zip file path (optional)')
    
    args = parser.parse_args()
    
    with open(args.proxies, 'r') as f:
        proxy_list = json.load(f)
    
    extensions = generate_proxy_extensions(args.template, args.output, proxy_list)
    print(f"Generated {len(extensions)} extensions at {args.output}")
    
    if args.zip:
        zip_path = create_zip_file(extensions, args.zip)
        print(f"Created zip file at {zip_path}")
