#!/usr/bin/env python3
"""
Script to rename claude-code.nvim to claude-code-ide.nvim
This includes renaming directories, files, and updating all references in the codebase.
"""

import os
import re
import shutil
import argparse
from pathlib import Path
from typing import List, Tuple, Dict

class RenameProject:
    def __init__(self, root_path: str, dry_run: bool = True):
        self.root_path = Path(root_path)
        self.dry_run = dry_run
        self.changes: List[str] = []
        
        # Define file extensions to process
        self.text_extensions = {'.lua', '.md', '.txt', '.sh', '.nix', '.yaml', '.yml', '.json'}
        self.special_files = {'Justfile', 'Makefile', 'LICENSE', 'CHANGELOG'}
        
        # Define replacement patterns
        self.replacements = [
            # Most specific patterns first
            (r'claude-code\.nvim', 'claude-code-ide.nvim'),
            (r'claude-code\.txt', 'claude-code-ide.txt'),
            (r'claude-code\.log', 'claude-code-ide.log'),
            (r'ianks/claude-code\.nvim', 'ianks/claude-code-ide.nvim'),
            
            # Lua require statements
            (r'require\("claude-code"\)', 'require("claude-code-ide")'),
            (r'require\("claude-code\.', 'require("claude-code-ide.'),
            (r"require\('claude-code'\)", "require('claude-code-ide')"),
            (r"require\('claude-code\.", "require('claude-code-ide."),
            
            # Events
            (r'claude-code:', 'claude-code-ide:'),
            
            # Help tags
            (r'\*claude-code-', '*claude-code-ide-'),
            
            # Paths
            (r'/claude-code/', '/claude-code-ide/'),
            (r'"claude-code/', '"claude-code-ide/'),
            (r"'claude-code/", "'claude-code-ide/"),
            
            # General references (be careful with this one)
            (r'(\s|^|")claude-code(\s|$|")', r'\1claude-code-ide\2'),
        ]
        
        # Directory and file renames
        self.path_renames = [
            ('lua/claude-code', 'lua/claude-code-ide'),
            ('doc/claude-code.txt', 'doc/claude-code-ide.txt'),
            ('plugin/claude-code.lua', 'plugin/claude-code-ide.lua'),
        ]

    def log(self, message: str):
        """Log a change or action"""
        self.changes.append(message)
        print(f"{'[DRY RUN] ' if self.dry_run else ''}{message}")

    def should_process_file(self, file_path: Path) -> bool:
        """Check if file should be processed for text replacements"""
        if file_path.name in self.special_files:
            return True
        return file_path.suffix in self.text_extensions

    def replace_in_file(self, file_path: Path):
        """Replace patterns in a single file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            original_content = content
            changes_made = []
            
            for pattern, replacement in self.replacements:
                new_content = re.sub(pattern, replacement, content)
                if new_content != content:
                    # Count occurrences
                    occurrences = len(re.findall(pattern, content))
                    changes_made.append(f"  - {pattern} → {replacement} ({occurrences} occurrences)")
                    content = new_content
            
            if content != original_content:
                self.log(f"Updating file: {file_path.relative_to(self.root_path)}")
                for change in changes_made:
                    self.log(change)
                
                if not self.dry_run:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(content)
                        
        except Exception as e:
            self.log(f"Error processing {file_path}: {e}")

    def rename_paths(self):
        """Rename directories and files"""
        for old_path, new_path in self.path_renames:
            old_full = self.root_path / old_path
            new_full = self.root_path / new_path
            
            if old_full.exists():
                self.log(f"Renaming: {old_path} → {new_path}")
                if not self.dry_run:
                    # Ensure parent directory exists
                    new_full.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(old_full), str(new_full))
            else:
                self.log(f"Warning: Path not found: {old_path}")

    def process_all_files(self):
        """Process all files in the project"""
        # Collect all files first to avoid issues with directory renames
        files_to_process = []
        
        for root, dirs, files in os.walk(self.root_path):
            root_path = Path(root)
            
            # Skip hidden directories and common build/dependency directories
            dirs[:] = [d for d in dirs if not d.startswith('.') and d not in {'node_modules', 'build', 'dist', '__pycache__'}]
            
            for file in files:
                file_path = root_path / file
                if self.should_process_file(file_path):
                    files_to_process.append(file_path)
        
        self.log(f"\nProcessing {len(files_to_process)} files...")
        for file_path in files_to_process:
            self.replace_in_file(file_path)

    def update_git_remote(self):
        """Update git remote URL if needed"""
        try:
            git_config = self.root_path / '.git' / 'config'
            if git_config.exists():
                with open(git_config, 'r') as f:
                    content = f.read()
                
                if 'claude-code.nvim' in content:
                    self.log("\nUpdating git remote URL...")
                    new_content = content.replace('claude-code.nvim', 'claude-code-ide.nvim')
                    
                    if not self.dry_run:
                        with open(git_config, 'w') as f:
                            f.write(new_content)
        except Exception as e:
            self.log(f"Warning: Could not update git config: {e}")

    def run(self):
        """Execute the rename process"""
        print(f"{'=' * 60}")
        print(f"Renaming claude-code.nvim to claude-code-ide.nvim")
        print(f"Root path: {self.root_path}")
        print(f"Mode: {'DRY RUN' if self.dry_run else 'EXECUTE'}")
        print(f"{'=' * 60}\n")
        
        # First rename directories and files
        self.log("Step 1: Renaming directories and files...")
        self.rename_paths()
        
        # Then process file contents
        self.log("\nStep 2: Updating file contents...")
        self.process_all_files()
        
        # Update git remote
        self.log("\nStep 3: Checking git configuration...")
        self.update_git_remote()
        
        # Summary
        print(f"\n{'=' * 60}")
        print(f"Summary: {len(self.changes)} changes {'would be' if self.dry_run else 'were'} made")
        print(f"{'=' * 60}")
        
        if self.dry_run:
            print("\nThis was a DRY RUN. No changes were made.")
            print("Run with --execute to apply changes.")

def main():
    parser = argparse.ArgumentParser(description='Rename claude-code.nvim to claude-code-ide.nvim')
    parser.add_argument('--execute', action='store_true', 
                        help='Execute the rename (default is dry run)')
    parser.add_argument('--path', type=str, default='.',
                        help='Root path of the project (default: current directory)')
    
    args = parser.parse_args()
    
    renamer = RenameProject(args.path, dry_run=not args.execute)
    renamer.run()

if __name__ == '__main__':
    main()