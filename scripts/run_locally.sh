#!/bin/bash

# Migration Planner Local Development Runner
# This script automates the local development setup and run process

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_podman_connection() {
    if command_exists podman; then
        print_status "Checking Podman connection..."
        
        if ! podman info >/dev/null 2>&1; then
            print_warning "Podman is not connected. Attempting to initialize and start Podman machine..."
            
            if ! podman machine list | grep -q "podman-machine-default"; then
                print_status "Creating Podman machine..."
                podman machine init
            fi
            
            print_status "Starting Podman machine..."
            podman machine start
            
            sleep 3
            
            if podman info >/dev/null 2>&1; then
                print_success "Podman machine is now running"
            else
                print_error "Failed to start Podman machine. Please run 'podman machine init' and 'podman machine start' manually."
                exit 1
            fi
        else
            print_success "Podman connection is working"
        fi
    fi
}

check_container_runtime() {
    if command_exists podman; then
        check_podman_connection
        return 0
    elif command_exists docker; then
        print_success "Docker is available"
        return 0
    else
        return 1
    fi
}

check_prerequisites() {
    print_status "Checking prerequisites..."
    
    local missing_deps=()
    
    if ! command_exists go; then
        missing_deps+=("Go 1.19 or later")
    fi
    
    if ! command_exists make; then
        missing_deps+=("Make")
    fi
    
    if ! command_exists git; then
        missing_deps+=("Git")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "Please install the missing dependencies and run this script again."
        exit 1
    fi
    
    if ! check_container_runtime; then
        print_error "Neither Docker nor Podman is available or working properly."
        echo "Please install Docker or Podman and ensure it's running."
        exit 1
    fi
    
    print_success "All prerequisites are installed and working"
}

check_project_root() {
    if [ ! -f "Makefile" ]; then
        print_error "Makefile not found. Please run this script from the project root directory."
        exit 1
    fi
}

build_project() {
    print_status "Building the project..."
    make build
}

setup_database() {
    print_status "Setting up the database..."
    
    if ! check_container_runtime; then
        print_error "Container runtime is not available. Cannot proceed with database setup."
        exit 1
    fi
    
    print_status "Stopping any existing database containers..."
    if ! make kill-db 2>/dev/null; then
        print_warning "Failed to stop existing database containers (this is usually fine if none were running)"
    fi
    
    print_status "Deploying fresh database..."
    if ! make deploy-db; then
        print_error "Failed to deploy database. Please check your container runtime setup."
        echo ""
        echo "If using Podman, try:"
        echo "  podman machine init"
        echo "  podman machine start"
        echo ""
        echo "If using Docker, ensure Docker Desktop is running."
        exit 1
    fi
    
    print_success "Database setup completed"
}

download_opa_policies() {
    print_status "Downloading OPA policies..."
    make setup-opa-policies
}

configure_environment() {
    print_status "Configuring environment variables..."    
    export MIGRATION_PLANNER_AGENT_AUTH_ENABLED=false
    export MIGRATION_PLANNER_AUTH=none
}

check_running() {
    local port="${1:-3443}"
    
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i ":$port" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -an | grep -q ":$port "; then
            return 0
        fi
    fi
    
    return 1
}

run_application() {
    print_status "Starting the Migration Planner API server..."
    
    if check_running 3443; then
        print_warning "Port 3443 is already in use. The application might already be running."
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Exiting..."
            exit 0
        fi
    fi
    
    print_success "Setup completed successfully!"
    echo ""
    print_warning "The Migration Planner API is starting..."
    print_warning "API will be available at: http://localhost:3443"
    print_warning "Press Ctrl+C to stop the application"
    echo ""
    print_status "You can test the API with: curl http://localhost:3443/api/v1/sources"
    echo ""
    
    trap cleanup_on_exit INT TERM
    
    make run
}

cleanup_on_exit() {
    echo ""
    print_status "Application stopped. Cleanup options:"
    echo ""
    echo "1. Clean up OPA policies (removes downloaded policies)"
    echo "2. Exit without cleanup"
    echo ""
    read -p "Choose an option (1-2): " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            print_status "Cleaning up OPA policies..."
            if make clean-opa-policies; then
                print_success "OPA policies cleaned up successfully"
            else
                print_warning "Failed to clean up OPA policies"
            fi
            ;;
        *)
            print_status "Exiting without cleanup."
            ;;
    esac
    
    echo ""
    print_success "Goodbye!"
    exit 0
}

show_troubleshooting() {
    echo ""
    echo "Troubleshooting:"
    echo "==============="
    echo ""
    echo "If you encounter Podman connection issues:"
    echo "  1. podman machine init"
    echo "  2. podman machine start"
    echo "  3. podman machine list"
    echo ""
    echo "If you encounter Docker issues:"
    echo "  1. Start Docker Desktop"
    echo "  2. docker info"
    echo ""
    echo "If database setup fails:"
    echo "  1. Check container runtime: podman info or docker info"
    echo "  2. For Podman: podman machine start"
    echo "  3. For Docker: Start Docker Desktop"
    echo ""
    echo "Manual database commands:"
    echo "  make kill-db    # Stop database"
    echo "  make deploy-db  # Start database"
    echo ""
    echo "Cleanup commands:"
    echo "  make clean-opa-policies  # Remove downloaded OPA policies"
    echo ""
    echo "Note: When you stop the application (Ctrl+C), you'll be prompted"
    echo "      with cleanup options including OPA policy cleanup."
    echo ""
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script automates the complete local development setup for Migration Planner:"
    echo "  1. Check prerequisites (including container runtime)"
    echo "  2. Build the project"
    echo "  3. Set up the database"
    echo "  4. Download OPA policies"
    echo "  5. Configure environment variables"
    echo "  6. Run the application"
    echo "  7. Cleanup options when exiting (including OPA policies)"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --build-only   Only build the project (skip database setup and running)"
    echo "  --no-db        Skip database setup"
    echo "  --no-opa       Skip OPA policies download"
    echo "  --no-run       Skip running the application"
    echo ""
    echo "Examples:"
    echo "  $0                    # Complete setup and run"
    echo "  $0 --build-only       # Only build the project"
    echo "  $0 --no-run           # Setup everything but don't run"
    echo ""
    echo "API Endpoints (when running):"
    echo "  - Sources:     curl http://localhost:3443/api/v1/sources"
    echo "  - Info:        curl http://localhost:3443/api/v1/info"
    echo "  - Assessments: curl http://localhost:3443/api/v1/assessments"
    
    show_troubleshooting
}

main() {
    local build_only=false
    local no_db=false
    local no_opa=false
    local no_run=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --build-only)
                build_only=true
                shift
                ;;
            --no-db)
                no_db=true
                shift
                ;;
            --no-opa)
                no_opa=true
                shift
                ;;
            --no-run)
                no_run=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "=========================================="
    echo "Migration Planner Local Development Setup"
    echo "=========================================="
    echo ""
    
    check_project_root
    check_prerequisites
    build_project
    
    if [ "$build_only" = true ]; then
        print_success "Build completed. Exiting as requested."
        exit 0
    fi
    
    if [ "$no_db" = false ]; then
        setup_database
    else
        print_warning "Skipping database setup as requested"
    fi
    
    if [ "$no_opa" = false ]; then
        download_opa_policies
    else
        print_warning "Skipping OPA policies download as requested"
    fi
    
    configure_environment
    
    if [ "$no_run" = false ]; then
        run_application
    else
        print_success "Setup completed. Application not started as requested."
        print_status "To run the application manually, use: make run"
    fi
}

main "$@"