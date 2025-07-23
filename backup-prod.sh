#!/bin/bash
# Wise Owl Production Backup Script
# Automated backup with rotation, compression, and restore functionality

set -e

# Configuration
BACKUP_ROOT="backups"
RETENTION_DAYS=7
MONGODB_CONTAINER_PREFIX="wo-mongodb"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Print functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status() {
    echo -e "${BLUE}[STATUS]${NC} $1"
}

# Get MongoDB container name
get_mongodb_container() {
    # Try to find the MongoDB container
    local container=$(docker ps --format "table {{.Names}}" | grep "$MONGODB_CONTAINER_PREFIX" | head -1)
    
    if [ -z "$container" ]; then
        print_error "MongoDB container not found!"
        echo "Expected container name pattern: $MONGODB_CONTAINER_PREFIX*"
        echo "Running containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}"
        exit 1
    fi
    
    echo "$container"
}

# Check if MongoDB is accessible
check_mongodb() {
    local container=$1
    
    if ! docker exec "$container" mongosh --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
        print_error "MongoDB is not accessible in container $container"
        exit 1
    fi
}

# Create backup
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKUP_ROOT/$timestamp"
    local mongodb_container
    
    print_info "Creating backup $timestamp..."
    
    # Get MongoDB container
    mongodb_container=$(get_mongodb_container)
    print_status "Using MongoDB container: $mongodb_container"
    
    # Check MongoDB accessibility
    check_mongodb "$mongodb_container"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Database list
    local databases=("users_db" "content_db" "quiz_db")
    
    # Backup each database
    for db in "${databases[@]}"; do
        print_status "Backing up database: $db"
        
        # Create dump
        docker exec "$mongodb_container" \
            mongodump --db="$db" --archive="/tmp/$db.archive" --quiet
        
        # Copy from container
        docker cp "$mongodb_container:/tmp/$db.archive" "$backup_dir/$db.archive"
        
        # Compress
        gzip "$backup_dir/$db.archive"
        
        # Clean up temp file in container
        docker exec "$mongodb_container" rm -f "/tmp/$db.archive"
        
        # Get compressed size
        local size=$(du -h "$backup_dir/$db.archive.gz" | cut -f1)
        echo -e "  ${GREEN}✅ $db ($size)${NC}"
    done
    
    # Create manifest file
    cat > "$backup_dir/manifest.txt" << EOF
Wise Owl Backup Manifest
========================
Timestamp: $timestamp
Created: $(date)
Databases: ${databases[*]}
MongoDB Container: $mongodb_container
Backup Method: mongodump + gzip
Files:
EOF
    
    # Add file details to manifest
    for db in "${databases[@]}"; do
        local size=$(du -h "$backup_dir/$db.archive.gz" | cut -f1)
        echo "  - $db.archive.gz ($size)" >> "$backup_dir/manifest.txt"
    done
    
    # Create compressed tarball
    print_status "Creating compressed archive..."
    tar -czf "$BACKUP_ROOT/wise-owl-backup-$timestamp.tar.gz" -C "$BACKUP_ROOT" "$timestamp"
    
    # Get final archive size
    local archive_size=$(du -h "$BACKUP_ROOT/wise-owl-backup-$timestamp.tar.gz" | cut -f1)
    
    # Clean up directory (keep only the tarball)
    rm -rf "$backup_dir"
    
    print_info "Backup completed successfully!"
    echo "  📦 Archive: wise-owl-backup-$timestamp.tar.gz ($archive_size)"
    echo "  📁 Location: $BACKUP_ROOT/"
    
    # Update manifest in the archive
    echo "Final archive size: $archive_size" >> "$BACKUP_ROOT/manifest-$timestamp.txt"
    
    # Log the backup
    echo "[$(date)] Backup created: wise-owl-backup-$timestamp.tar.gz ($archive_size)" >> "$BACKUP_ROOT/backup.log"
}

# Rotate old backups
rotate_backups() {
    print_info "Rotating old backups (keeping $RETENTION_DAYS days)..."
    
    local deleted_count=0
    local total_size=0
    
    # Find and process old backups
    while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        local size=$(du -b "$file" | cut -f1)
        
        total_size=$((total_size + size))
        rm "$file"
        deleted_count=$((deleted_count + 1))
        
        echo "  🗑️  Removed: $filename"
        echo "[$(date)] Backup deleted (rotation): $filename" >> "$BACKUP_ROOT/backup.log"
        
    done < <(find "$BACKUP_ROOT" -name "wise-owl-backup-*.tar.gz" -mtime +$RETENTION_DAYS -print0 2>/dev/null)
    
    if [ $deleted_count -eq 0 ]; then
        print_info "No old backups to rotate"
    else
        local size_mb=$((total_size / 1024 / 1024))
        print_info "Rotation complete: $deleted_count backups removed (${size_mb}MB freed)"
    fi
}

# List available backups
list_backups() {
    print_info "Available backups in $BACKUP_ROOT:"
    echo ""
    
    if ! ls "$BACKUP_ROOT"/wise-owl-backup-*.tar.gz >/dev/null 2>&1; then
        print_warning "No backups found"
        return
    fi
    
    printf "%-30s %-10s %-20s\n" "BACKUP FILE" "SIZE" "DATE"
    echo "--------------------------------------------------------------"
    
    for backup in "$BACKUP_ROOT"/wise-owl-backup-*.tar.gz; do
        local filename=$(basename "$backup")
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$backup" 2>/dev/null || stat -c "%y" "$backup" | cut -d' ' -f1,2 | cut -d':' -f1,2)
        
        printf "%-30s %-10s %-20s\n" "$filename" "$size" "$date"
    done
    
    echo ""
    
    # Show total backup size
    local total_size=$(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1 || echo "Unknown")
    print_info "Total backup storage used: $total_size"
}

# Restore backup
restore_backup() {
    local backup_file=$1
    
    if [ -z "$backup_file" ]; then
        print_error "Please specify backup file"
        echo ""
        list_backups
        echo ""
        echo "Usage: $0 restore <backup-file>"
        echo "Example: $0 restore $BACKUP_ROOT/wise-owl-backup-20240124_120000.tar.gz"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    # Confirmation prompt
    print_warning "⚠️  WARNING: This will REPLACE existing database data!"
    read -p "Are you sure you want to restore from $(basename "$backup_file")? (type 'YES' to confirm): " -r
    
    if [ "$REPLY" != "YES" ]; then
        print_info "Restore cancelled"
        exit 0
    fi
    
    local mongodb_container
    mongodb_container=$(get_mongodb_container)
    
    print_info "Restoring from $(basename "$backup_file")..."
    print_status "Using MongoDB container: $mongodb_container"
    
    # Check MongoDB accessibility
    check_mongodb "$mongodb_container"
    
    # Extract backup to temporary directory
    local temp_dir=$(mktemp -d)
    print_status "Extracting backup..."
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Find the backup directory (should be only one)
    local backup_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    
    if [ -z "$backup_dir" ]; then
        print_error "No backup directory found in archive"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Show manifest if available
    if [ -f "$backup_dir/manifest.txt" ]; then
        print_status "Backup manifest:"
        cat "$backup_dir/manifest.txt" | sed 's/^/  /'
        echo ""
    fi
    
    # Restore each database
    for db_archive in "$backup_dir"/*.archive.gz; do
        if [ ! -f "$db_archive" ]; then
            continue
        fi
        
        local db_name=$(basename "$db_archive" .archive.gz)
        print_status "Restoring database: $db_name"
        
        # Decompress to temp file
        local temp_archive="/tmp/restore_$db_name.archive"
        gunzip -c "$db_archive" > "$temp_archive"
        
        # Copy to container
        docker cp "$temp_archive" "$mongodb_container:/tmp/restore_$db_name.archive"
        
        # Restore database (--drop removes existing data)
        docker exec "$mongodb_container" \
            mongorestore --db="$db_name" --archive="/tmp/restore_$db_name.archive" --drop --quiet
        
        # Clean up
        rm -f "$temp_archive"
        docker exec "$mongodb_container" rm -f "/tmp/restore_$db_name.archive"
        
        echo -e "  ${GREEN}✅ $db_name restored${NC}"
    done
    
    # Cleanup temp directory
    rm -rf "$temp_dir"
    
    print_info "Restore completed successfully! 🎉"
    echo "[$(date)] Restore completed from: $(basename "$backup_file")" >> "$BACKUP_ROOT/backup.log"
}

# Verify backup
verify_backup() {
    local backup_file=$1
    
    if [ -z "$backup_file" ]; then
        print_error "Please specify backup file to verify"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    print_info "Verifying backup: $(basename "$backup_file")"
    
    # Test archive integrity
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Archive integrity OK${NC}"
    else
        echo -e "  ${RED}❌ Archive is corrupted${NC}"
        exit 1
    fi
    
    # Extract and check contents
    local temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null
    
    local backup_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    
    if [ -d "$backup_dir" ]; then
        echo -e "  ${GREEN}✅ Backup directory structure OK${NC}"
        
        # Check for expected database files
        local expected_dbs=("users_db" "content_db" "quiz_db")
        for db in "${expected_dbs[@]}"; do
            if [ -f "$backup_dir/$db.archive.gz" ]; then
                echo -e "  ${GREEN}✅ Database $db present${NC}"
            else
                echo -e "  ${YELLOW}⚠️  Database $db missing${NC}"
            fi
        done
        
        # Show manifest if available
        if [ -f "$backup_dir/manifest.txt" ]; then
            echo ""
            print_status "Backup manifest:"
            cat "$backup_dir/manifest.txt" | sed 's/^/  /'
        fi
    else
        echo -e "  ${RED}❌ Invalid backup structure${NC}"
    fi
    
    rm -rf "$temp_dir"
    print_info "Verification complete"
}

# Show usage
show_usage() {
    echo "🦉 Wise Owl Backup Management"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  create           - Create new backup with rotation"
    echo "  restore <file>   - Restore from backup file"
    echo "  list             - List available backups"
    echo "  verify <file>    - Verify backup file integrity"
    echo "  rotate           - Manually rotate old backups"
    echo "  clean            - Interactive cleanup of old backups"
    echo ""
    echo "Examples:"
    echo "  $0 create"
    echo "  $0 restore $BACKUP_ROOT/wise-owl-backup-20240124_120000.tar.gz"
    echo "  $0 list"
    echo "  $0 verify $BACKUP_ROOT/wise-owl-backup-20240124_120000.tar.gz"
    echo ""
    echo "Configuration:"
    echo "  Backup directory: $BACKUP_ROOT"
    echo "  Retention: $RETENTION_DAYS days"
    echo "  MongoDB container pattern: $MONGODB_CONTAINER_PREFIX*"
    echo ""
}

# Interactive cleanup
interactive_cleanup() {
    print_info "Interactive backup cleanup"
    
    if ! ls "$BACKUP_ROOT"/wise-owl-backup-*.tar.gz >/dev/null 2>&1; then
        print_info "No backups found to clean up"
        return
    fi
    
    echo ""
    list_backups
    echo ""
    
    print_warning "Select backups to delete (be careful!):"
    
    local files=("$BACKUP_ROOT"/wise-owl-backup-*.tar.gz)
    local i=1
    
    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        local size=$(du -h "$file" | cut -f1)
        echo "  $i) $filename ($size)"
        i=$((i + 1))
    done
    
    echo ""
    read -p "Enter numbers to delete (space-separated) or 'all' for all, 'none' to cancel: " -r
    
    if [ "$REPLY" = "none" ] || [ -z "$REPLY" ]; then
        print_info "Cleanup cancelled"
        return
    fi
    
    if [ "$REPLY" = "all" ]; then
        read -p "Are you sure you want to delete ALL backups? (type 'YES'): " -r
        if [ "$REPLY" = "YES" ]; then
            rm -f "$BACKUP_ROOT"/wise-owl-backup-*.tar.gz
            print_info "All backups deleted"
        else
            print_info "Cleanup cancelled"
        fi
        return
    fi
    
    # Delete selected backups
    for num in $REPLY; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#files[@]}" ]; then
            local file="${files[$((num-1))]}"
            local filename=$(basename "$file")
            rm "$file"
            print_info "Deleted: $filename"
        else
            print_warning "Invalid selection: $num"
        fi
    done
}

# Ensure backup directory exists
mkdir -p "$BACKUP_ROOT"

# Main command dispatcher
case "${1:-help}" in
    "create")
        create_backup
        rotate_backups
        ;;
    
    "restore")
        restore_backup "$2"
        ;;
    
    "list")
        list_backups
        ;;
    
    "verify")
        verify_backup "$2"
        ;;
    
    "rotate")
        rotate_backups
        ;;
    
    "clean")
        interactive_cleanup
        ;;
    
    "help"|"-h"|"--help")
        show_usage
        ;;
    
    *)
        echo "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
