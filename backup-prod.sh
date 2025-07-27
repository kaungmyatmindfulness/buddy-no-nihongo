#!/bin/bash
# Wise Owl Production Backup Script
# This script handles database backups and data archiving

set -e

# Load common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/scripts/utils/common.sh" ]; then
    source "$SCRIPT_DIR/scripts/utils/common.sh"
else
    # Fallback print functions
    print_info() { echo "[INFO] $1"; }
    print_error() { echo "[ERROR] $1"; }
    print_success() { echo "[SUCCESS] $1"; }
    print_warning() { echo "[WARN] $1"; }
fi

# Configuration
BACKUP_DIR="$SCRIPT_DIR/backups"
DATE_FORMAT=$(date +%Y%m%d_%H%M%S)
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
MONGODB_CONTAINER="wo-mongodb"
RETENTION_DAYS=30

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Usage function
usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  create    - Create a new backup"
    echo "  restore   - Restore from backup"
    echo "  list      - List available backups"
    echo "  cleanup   - Remove old backups"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 create"
    echo "  $0 restore backup_20240727_140000"
    echo "  $0 cleanup"
}

# Check if MongoDB container is running
check_mongodb() {
    if ! docker ps --format "{{.Names}}" | grep -q "^$MONGODB_CONTAINER$"; then
        print_error "MongoDB container '$MONGODB_CONTAINER' is not running"
        print_info "Start services with: docker compose up -d"
        exit 1
    fi
}

# Create backup
create_backup() {
    print_info "Creating backup for Wise Owl databases..."
    
    check_mongodb
    
    local backup_name="wise-owl-backup_$DATE_FORMAT"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$backup_path"
    
    # Backup individual databases
    databases=("users_db" "content_db" "quiz_db")
    
    for db in "${databases[@]}"; do
        print_info "Backing up database: $db"
        
        if docker exec "$MONGODB_CONTAINER" mongodump \
            --db "$db" \
            --out "/tmp/backup" \
            --quiet; then
            
            # Copy backup from container
            docker cp "$MONGODB_CONTAINER:/tmp/backup/$db" "$backup_path/"
            
            # Clean up container temp backup
            docker exec "$MONGODB_CONTAINER" rm -rf "/tmp/backup"
            
            print_success "✅ $db backed up successfully"
        else
            print_error "❌ Failed to backup $db"
            return 1
        fi
    done
    
    # Create backup metadata
    cat > "$backup_path/backup_info.json" << EOF
{
    "backup_name": "$backup_name",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "databases": ["users_db", "content_db", "quiz_db"],
    "mongodb_version": "$(docker exec $MONGODB_CONTAINER mongosh --quiet --eval 'db.version()')",
    "wise_owl_version": "$(cd $SCRIPT_DIR && git rev-parse HEAD 2>/dev/null || echo 'unknown')"
}
EOF
    
    # Compress backup
    print_info "Compressing backup..."
    cd "$BACKUP_DIR"
    tar -czf "${backup_name}.tar.gz" "$backup_name"
    rm -rf "$backup_name"
    
    local backup_size=$(du -h "${backup_name}.tar.gz" | cut -f1)
    print_success "✅ Backup created: ${backup_name}.tar.gz ($backup_size)"
    
    # Show backup info
    print_info "Backup details:"
    echo "  📁 Location: $BACKUP_DIR/${backup_name}.tar.gz"
    echo "  📊 Size: $backup_size"
    echo "  🕒 Created: $(date)"
    echo "  🗃️  Databases: users_db, content_db, quiz_db"
}

# List backups
list_backups() {
    print_info "Available backups:"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
        print_warning "No backups found in $BACKUP_DIR"
        return 0
    fi
    
    echo "📋 Backup Files:"
    echo "┌─────────────────────────────────┬──────────┬─────────────────────┐"
    echo "│ Backup Name                     │ Size     │ Created             │"
    echo "├─────────────────────────────────┼──────────┼─────────────────────┤"
    
    for backup_file in "$BACKUP_DIR"/*.tar.gz; do
        if [ -f "$backup_file" ]; then
            local name=$(basename "$backup_file" .tar.gz)
            local size=$(du -h "$backup_file" | cut -f1)
            local created=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null || date -r "$backup_file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
            
            printf "│ %-31s │ %-8s │ %-19s │\n" "$name" "$size" "$created"
        fi
    done
    
    echo "└─────────────────────────────────┴──────────┴─────────────────────┘"
    echo ""
    
    local total_backups=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    
    print_info "Total: $total_backups backup(s), $total_size"
}

# Restore backup
restore_backup() {
    local backup_name="$1"
    
    if [ -z "$backup_name" ]; then
        print_error "Please specify a backup name"
        echo ""
        print_info "Available backups:"
        list_backups
        exit 1
    fi
    
    local backup_file="$BACKUP_DIR/${backup_name}.tar.gz"
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    print_warning "⚠️  This will restore databases and overwrite current data!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Restore cancelled"
        exit 0
    fi
    
    check_mongodb
    
    print_info "Restoring backup: $backup_name"
    
    # Extract backup
    cd "$BACKUP_DIR"
    tar -xzf "${backup_name}.tar.gz"
    
    # Restore databases
    for db_dir in "$backup_name"/*/; do
        if [ -d "$db_dir" ]; then
            local db_name=$(basename "$db_dir")
            print_info "Restoring database: $db_name"
            
            # Copy to container
            docker cp "$db_dir" "$MONGODB_CONTAINER:/tmp/restore/"
            
            # Drop existing database and restore
            docker exec "$MONGODB_CONTAINER" sh -c "
                mongosh --quiet --eval 'db.dropDatabase()' '$db_name' &&
                mongorestore --db '$db_name' '/tmp/restore/$db_name' &&
                rm -rf '/tmp/restore'
            "
            
            if [ $? -eq 0 ]; then
                print_success "✅ $db_name restored successfully"
            else
                print_error "❌ Failed to restore $db_name"
            fi
        fi
    done
    
    # Clean up extracted files
    rm -rf "$backup_name"
    
    print_success "✅ Backup restore completed"
}

# Cleanup old backups
cleanup_backups() {
    print_info "Cleaning up backups older than $RETENTION_DAYS days..."
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_info "No backup directory found"
        return 0
    fi
    
    local removed_count=0
    
    # Find and remove old backups
    find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$RETENTION_DAYS -print0 | while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        print_info "Removing old backup: $filename"
        rm "$file"
        ((removed_count++))
    done
    
    if [ $removed_count -eq 0 ]; then
        print_info "No old backups found to remove"
    else
        print_success "✅ Removed $removed_count old backup(s)"
    fi
}

# Main script logic
case "${1:-help}" in
    "create")
        create_backup
        ;;
    "restore")
        restore_backup "$2"
        ;;
    "list")
        list_backups
        ;;
    "cleanup")
        cleanup_backups
        ;;
    "help"|"-h"|"--help")
        usage
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        usage
        exit 1
        ;;
esac
