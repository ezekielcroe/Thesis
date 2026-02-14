import os

# --- CONFIGURATION ---
# Extensions to include
ALLOWED_EXTENSIONS = {
    ".swift",
    ".cpp", 
    ".xcprivacy", 
    ".plist"
}

# Directories to ignore
IGNORE_DIRS = {
    "Pods", 
    ".git", 
    "DerivedData", 
    "Assets.xcassets", 
    "Preview Content", 
    "fastlane",
    "build"
}

# Output file name
OUTPUT_FILE = "FullProjectSource.txt"

def write_tree_structure(startpath, outfile):
    outfile.write("PROJECT STRUCTURE:\n")
    outfile.write("==================\n")
    
    for root, dirs, files in os.walk(startpath):
        # Remove ignored directories from traversal
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
        
        # Calculate indentation level
        level = root.replace(startpath, '').count(os.sep)
        indent = ' ' * 4 * level
        outfile.write(f"{indent}{os.path.basename(root)}/\n")
        
        # Write files that match allowed extensions
        subindent = ' ' * 4 * (level + 1)
        for f in files:
            ext = os.path.splitext(f)[1]
            if ext in ALLOWED_EXTENSIONS:
                outfile.write(f"{subindent}{f}\n")
    
    outfile.write("\n\n")

def merge_files():
    # Get current directory
    root_dir = os.getcwd()
    
    with open(OUTPUT_FILE, "w", encoding="utf-8") as outfile:
        # Step 1: Write the folder structure
        print("Generating folder structure...")
        write_tree_structure(root_dir, outfile)
        
        # Step 2: Write the file contents
        print("Merging file contents...")
        for dirpath, dirnames, filenames in os.walk(root_dir):
            # Remove ignored directories from traversal
            dirnames[:] = [d for d in dirnames if d not in IGNORE_DIRS]
            
            for filename in filenames:
                # Check extension
                ext = os.path.splitext(filename)[1]
                if ext in ALLOWED_EXTENSIONS:
                    file_path = os.path.join(dirpath, filename)
                    
                    # Create a relative path for cleaner reading
                    relative_path = os.path.relpath(file_path, root_dir)
                    
                    # Formatting the header for the output file
                    separator = "=" * 50
                    outfile.write(f"{separator}\n")
                    outfile.write(f"FILE: {relative_path}\n")
                    outfile.write(f"{separator}\n\n")
                    
                    try:
                        with open(file_path, "r", encoding="utf-8", errors="ignore") as infile:
                            outfile.write(infile.read())
                            outfile.write("\n\n")
                    except Exception as e:
                        print(f"Could not read {relative_path}: {e}")

    print(f"✅ Success! Structure and code combined into: {OUTPUT_FILE}")

if __name__ == "__main__":
    merge_files()