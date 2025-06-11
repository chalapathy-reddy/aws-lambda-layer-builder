#!/bin/bash

# Script to build an AWS Lambda layer for a specified Python version and architecture.
# Supports a custom requirements.txt file path.
# Usage: ./build_lambda_layer.sh [options] [python_version] [architecture]
# Example: ./build_lambda_layer.sh --requirements ./path/to/requirements.txt 3.9 ARM_64

# Version
VERSION="1.0.0"

# Function to display help
show_help() {
  echo "Usage: $(basename "$0") [options] [python_version] [architecture]"
  echo "Builds an AWS Lambda layer for a specified Python version and architecture."
  echo ""
  echo "Arguments:"
  echo "  python_version    Python version (e.g., 3.9, 3.10). If not provided, prompts for input."
  echo "  architecture      Architecture (ARM_64 or AMD_86). If not provided, prompts for input."
  echo ""
  echo "Options:"
  echo "  -h, --help        Display this help message and exit."
  echo "  -r, --requirements  Path to requirements.txt file (default: ./requirements.txt)."
  echo "  -v, --version     Display script version and exit."
  echo ""
  echo "Example:"
  echo "  ./build_lambda_layer.sh --requirements ./custom/requirements.txt 3.9 ARM_64"
  exit 0
}

# Function to display version
show_version() {
  echo "$(basename "$0") version $VERSION"
  exit 0
}

# Function to check if a command exists
check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "Error: Required command '$1' is not installed. Please install it and try again."
    exit 1
  fi
}

# Default requirements file path
requirements_file="./requirements.txt"

# Parse command-line options
while [[ "$1" =~ ^- ]]; do
  case "$1" in
    -h|--help)
      show_help
      ;;
    -r|--requirements)
      requirements_file="$2"
      shift 2
      ;;
    -v|--version)
      show_version
      ;;
    *)
      echo "Error: Unknown option $1"
      show_help
      exit 1
      ;;
  esac
done

# Check for required commands
check_command pip3
check_command zip

# Get Python version
if [ -z "$1" ]; then
  read -p "Please enter the Python version (e.g., 3.9): " python_version
else
  python_version="$1"
fi

# Validate Python version format
if [[ ! "$python_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Invalid Python version format. Use format like 3.9 or 3.10."
  exit 1
fi

# Check if Python version is supported (example: 3.8, 3.9, 3.10, 3.11, 3.12)
supported_versions=("3.8" "3.9" "3.10" "3.11" "3.12")
if ! [[ " ${supported_versions[*]} " =~ " ${python_version} " ]]; then
  echo "Error: Python version $python_version is not supported. Supported versions: ${supported_versions[*]}"
  exit 1
fi
echo "Python version: $python_version"

# Get architecture
if [ -z "$2" ]; then
  echo "Please select the architecture for the Lambda:"
  echo "1. ARM_64"
  echo "2. AMD_86"
  read -p "Enter 1 or 2: " platform_choice
else
  platform_choice="$2"
fi

# Map architecture input to platform
case "$platform_choice" in
  "1"|"ARM_64")
    platform="manylinux2014_aarch64"
    arch_name="ARM_64"
    ;;
  "2"|"AMD_86")
    platform="manylinux2014_x86_64"
    arch_name="AMD_86"
    ;;
  *)
    echo "Error: Invalid architecture. Use 1 (ARM_64) or 2 (AMD_86), or pass ARM_64/AMD_86 as argument."
    exit 1
    ;;
esac
echo "Architecture: $arch_name ($platform)"

# Check if requirements file exists and is readable
if [ ! -f "$requirements_file" ]; then
  echo "Error: Requirements file not found at '$requirements_file'."
  exit 1
fi
if [ ! -r "$requirements_file" ]; then
  echo "Error: Requirements file '$requirements_file' is not readable."
  exit 1
fi
echo "Using requirements file: $requirements_file"

# Clean up previous layers directory
echo "Cleaning up previous layers directory..."
rm -rf ./layers
mkdir -p layers/python/lib || {
  echo "Error: Failed to create layers directory."
  exit 1
}

# Build the Lambda layer
echo "Building Lambda layer for Python $python_version with $arch_name architecture..."
pip3 install \
  --platform "$platform" \
  --target "layers/python/lib/python${python_version}/site-packages" \
  --implementation cp \
  --python-version "$python_version" \
  -r "$requirements_file" \
  --only-binary=:all: || {
  echo "Error: Failed to install dependencies with pip. Check your requirements.txt or network connection."
  exit 1
}

# Verify that the target directory contains installed packages
if [ ! -d "layers/python/lib/python${python_version}/site-packages" ] || [ -z "$(ls -A layers/python/lib/python${python_version}/site-packages)" ]; then
  echo "Error: No packages were installed in the target directory. Check your requirements.txt."
  exit 1
}

# Create the zip file
echo "Zipping the Lambda layer..."
cd layers || {
  echo "Error: Failed to change to layers directory."
  exit 1
}
zip -r9 aws_lambda_layer.zip . || {
  echo "Error: Failed to create zip file."
  exit 1
}
cd .. || {
  echo "Error: Failed to return to parent directory."
  exit 1
}

# Verify zip file exists
if [ ! -f "layers/aws_lambda_layer.zip" ]; then
  echo "Error: Zip file was not created."
  exit 1
fi

echo "Successfully built Lambda layer: $(pwd)/layers/aws_lambda_layer.zip"