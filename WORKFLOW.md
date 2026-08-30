# Hugo Site Workflow Setup

## Problem Summary
The original setup was complex and error-prone:
- Submodule configuration issues (detached HEAD states)
- Manual syncing between source and built site
- Multiple git operations required for simple changes
- Confusing remote URLs

## Solution: Clean Repository Configuration

### Repository Structure
```
theunfedwatchdog/                          (Parent - source repo)
├── build_and_deploy.sh                    (Automated build script)
├── theunfedwatchdog/                      (Hugo project)
│   ├── content/                           (Blog posts)
│   ├── static/
│   │   └── docs/resume/
│   │       └── akshat_sharma_cv.pdf       (CV - synced from Downloads)
│   ├── themes/
│   │   └── PaperMod/                      (Git clone, not submodule)
│   ├── public/                            (Built site - GENERATED)
│   └── hugo.toml                          (Hugo config)
└── .gitmodules                            (Only public/ is a submodule)

Remote Configuration:
- Parent repo:    github.com/AkshatSharma05/theunfedwatchdog.git (source code)
- Public submodule: github.com/AkshatSharma05/theunfedwatchdog.github.io.git (GitHub Pages)
```

## Workflow: Making Changes

### For Content Changes (blog posts, etc.)
```bash
# 1. Edit your content in theunfedwatchdog/content/posts/
# 2. Run the build script
cd /home/hominum/projects/theunfedwatchdog
./build_and_deploy.sh
```

### For CV Updates
```bash
# 1. Save your new CV as ~/Downloads/AKSHAT_SHARMA_RESUME.pdf
# 2. Run the build script (it auto-detects and copies the CV)
cd /home/hominum/projects/theunfedwatchdog
./build_and_deploy.sh
```

### For Theme Changes
```bash
# 1. Edit theme files in theunfedwatchdog/theunfedwatchdog/themes/PaperMod/
# 2. Run the build script
cd /home/hominum/projects/theunfedwatchdog
./build_and_deploy.sh
```

## What the Build Script Does

The `build_and_deploy.sh` script automates the entire process:

1. **Updates CV** - Checks for `~/Downloads/AKSHAT_SHARMA_RESUME.pdf` and copies it if found
2. **Builds Hugo** - Rebuilds the entire site with correct production URLs
3. **Syncs files** - Copies built site to the public submodule
4. **Commits & pushes** - Commits changes in both repositories and pushes to GitHub

All in one command! No manual git operations needed.

## Configuration Details

### Submodule Configuration (.gitmodules)
```
[submodule "theunfedwatchdog/public"]
    path = theunfedwatchdog/public
    url = git@github.com:AkshatSharma05/theunfedwatchdog.github.io.git
    branch = main
```

### Key Settings
- **baseURL**: `https://akshatsharma05.github.io/` (in hugo.toml)
- **Theme**: PaperMod (cloned to `themes/PaperMod/`, NOT a submodule)
- **Submodule branch**: `main` (ensures consistent tracking)

## Troubleshooting

### If submodule enters detached HEAD state
```bash
cd theunfedwatchdog/theunfedwatchdog/public
git checkout main
git pull origin main
```

### If you need to manually commit
```bash
cd /home/hominum/projects/theunfedwatchdog

# Check status
git status

# Commit changes
git add .
git commit -m "Your message"
git push origin main
```

### To verify the setup is correct
```bash
cd /home/hominum/projects/theunfedwatchdog
git config -f .gitmodules --get-regexp path
# Should show: submodule.theunfedwatchdog/public.path theunfedwatchdog/public

cd theunfedwatchdog/public
git branch  # Should show: * main
git remote -v  # Should show GitHub Pages repo
```

## Important Files

- **build_and_deploy.sh** - Run this for all deployments
- **theunfedwatchdog/hugo.toml** - Hugo configuration
- **theunfedwatchdog/content/posts/** - Your blog posts
- **theunfedwatchdog/static/docs/resume/akshat_sharma_cv.pdf** - Your CV
