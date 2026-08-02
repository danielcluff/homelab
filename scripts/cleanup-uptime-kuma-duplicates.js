#!/usr/bin/env node
/**
 * Uptime Kuma Cleanup Script
 * Removes duplicate monitors by name, keeping the oldest one (lowest ID)
 *
 * Requirements: npm install socket.io-client
 * Usage: node cleanup-uptime-kuma-duplicates.js
 *
 * Options:
 *   --dry-run    Show what would be deleted without actually deleting
 */

const io = require('socket.io-client');

// Configuration
const UPTIME_KUMA_URL = process.env.UPTIME_KUMA_URL || 'https://uptime.elate.me';
const USERNAME = process.env.UPTIME_KUMA_USERNAME;
const PASSWORD = process.env.UPTIME_KUMA_PASSWORD;
const DRY_RUN = process.argv.includes('--dry-run');

if (!USERNAME || !PASSWORD) {
    console.error('Set UPTIME_KUMA_USERNAME and UPTIME_KUMA_PASSWORD before running this script.');
    process.exit(1);
}

console.log('=========================================');
console.log('Uptime Kuma Duplicate Cleanup Script');
console.log('=========================================\n');

if (DRY_RUN) {
    console.log('*** DRY RUN MODE - No changes will be made ***\n');
}

// Connect to Socket.IO
console.log(`Connecting to ${UPTIME_KUMA_URL}...`);
const socket = io(UPTIME_KUMA_URL, {
    rejectUnauthorized: false, // Allow self-signed certs
    transports: ['polling', 'websocket']
});

let allMonitors = {};

socket.on('connect', () => {
    console.log('Connected to Uptime Kuma\n');

    // Login
    console.log(`Logging in as ${USERNAME}...`);
    socket.emit('login', {
        username: USERNAME,
        password: PASSWORD,
        token: null
    }, (res) => {
        if (res.ok) {
            console.log('Login successful\n');
            // Wait for monitor list to be populated
            setTimeout(findAndCleanupDuplicates, 2000);
        } else {
            console.error('ERROR: Login failed');
            console.error('Response:', res.msg);
            process.exit(1);
        }
    });
});

// Collect monitors as they come in
socket.on('monitorList', (monitors) => {
    allMonitors = monitors;
});

socket.on('connect_error', (error) => {
    console.error('Connection error:', error.message);
    process.exit(1);
});

function findAndCleanupDuplicates() {
    const monitorArray = Object.values(allMonitors);

    if (monitorArray.length === 0) {
        console.log('No monitors found. Make sure you have monitors configured.');
        socket.disconnect();
        process.exit(0);
    }

    console.log(`Found ${monitorArray.length} total monitors\n`);

    // Group monitors by name
    const monitorsByName = {};
    monitorArray.forEach(monitor => {
        const name = monitor.name;
        if (!monitorsByName[name]) {
            monitorsByName[name] = [];
        }
        monitorsByName[name].push(monitor);
    });

    // Find duplicates
    const duplicatesToDelete = [];
    const summary = [];

    Object.entries(monitorsByName).forEach(([name, monitors]) => {
        if (monitors.length > 1) {
            // Sort by ID (lowest first - oldest)
            monitors.sort((a, b) => a.id - b.id);

            const keep = monitors[0];
            const remove = monitors.slice(1);

            summary.push({
                name,
                keepId: keep.id,
                removeIds: remove.map(m => m.id),
                count: monitors.length
            });

            duplicatesToDelete.push(...remove);
        }
    });

    if (duplicatesToDelete.length === 0) {
        console.log('No duplicates found! Your Uptime Kuma is clean.');
        socket.disconnect();
        process.exit(0);
    }

    // Print summary
    console.log('=========================================');
    console.log('Duplicate Monitors Found:');
    console.log('=========================================\n');

    summary.forEach(item => {
        console.log(`"${item.name}" (${item.count} instances)`);
        console.log(`  Keeping:   ID ${item.keepId}`);
        console.log(`  Deleting:  IDs ${item.removeIds.join(', ')}`);
        console.log('');
    });

    console.log(`Total monitors to delete: ${duplicatesToDelete.length}\n`);

    if (DRY_RUN) {
        console.log('*** DRY RUN - No monitors were deleted ***');
        console.log('Run without --dry-run to actually delete duplicates.');
        socket.disconnect();
        process.exit(0);
    }

    // Delete duplicates
    console.log('Deleting duplicates...\n');

    let deleted = 0;
    let failed = 0;

    const deleteNext = (index) => {
        if (index >= duplicatesToDelete.length) {
            // All done
            console.log('\n=========================================');
            console.log('Cleanup Complete!');
            console.log('=========================================');
            console.log(`Deleted: ${deleted} monitors`);
            if (failed > 0) {
                console.log(`Failed:  ${failed} monitors`);
            }
            console.log(`\nVisit ${UPTIME_KUMA_URL} to verify.\n`);
            socket.disconnect();
            process.exit(failed > 0 ? 1 : 0);
            return;
        }

        const monitor = duplicatesToDelete[index];

        socket.emit('deleteMonitor', monitor.id, (res) => {
            if (res.ok) {
                console.log(`  Deleted: "${monitor.name}" (ID: ${monitor.id})`);
                deleted++;
            } else {
                console.log(`  Failed to delete: "${monitor.name}" (ID: ${monitor.id}) - ${res.msg}`);
                failed++;
            }

            // Small delay between deletions
            setTimeout(() => deleteNext(index + 1), 100);
        });
    };

    deleteNext(0);
}

// Handle timeout
setTimeout(() => {
    console.error('\nERROR: Script timed out after 60 seconds');
    process.exit(1);
}, 60000);
