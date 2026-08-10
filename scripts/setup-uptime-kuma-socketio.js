#!/usr/bin/env node
/**
 * Uptime Kuma Setup Script (Socket.IO version)
 * Configures monitors programmatically using Socket.IO client
 *
 * Requirements: npm install socket.io-client
 * Usage: node setup-uptime-kuma-socketio.js
 *
 * Note: This script checks for existing monitors by name before creating
 *       to prevent duplicates.
 */

const io = require('socket.io-client');

// Configuration
const UPTIME_KUMA_URL = process.env.UPTIME_KUMA_URL || 'https://uptime.elate.me';
const USERNAME = process.env.UPTIME_KUMA_USERNAME;
const PASSWORD = process.env.UPTIME_KUMA_PASSWORD;

if (!USERNAME || !PASSWORD) {
    console.error('Set UPTIME_KUMA_USERNAME and UPTIME_KUMA_PASSWORD before running this script.');
    process.exit(1);
}

console.log('=========================================');
console.log('Uptime Kuma Setup Script (Socket.IO)');
console.log('=========================================\n');

// Connect to Socket.IO
console.log(`Connecting to ${UPTIME_KUMA_URL}...`);
const socket = io(UPTIME_KUMA_URL, {
    rejectUnauthorized: false, // Allow self-signed certs
    transports: ['polling', 'websocket']
});

// Store existing monitors
let existingMonitors = {};

// Collect monitors as they come in
socket.on('monitorList', (monitors) => {
    existingMonitors = monitors;
});

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
            // Wait for monitor list to be populated before setup
            setTimeout(setupMonitors, 2000);
        } else {
            console.error('ERROR: Login failed');
            console.error('Response:', res.msg);
            process.exit(1);
        }
    });
});

socket.on('connect_error', (error) => {
    console.error('Connection error:', error.message);
    process.exit(1);
});

// Monitor configuration
const monitors = [
    // External services (HTTPS)
    { name: 'Elate.me Public Site', type: 'http', url: 'https://elate.me' },
    { name: 'Elate.biz Public Site', type: 'http', url: 'https://elate.biz' },
    { name: 'Grafana', type: 'http', url: 'https://grafana.elate.me' },
    { name: 'Longhorn UI', type: 'http', url: 'https://longhorn.elate.me' },
    { name: 'Pi-hole Admin', type: 'http', url: 'https://pihole.elate.me/admin' },
    { name: 'Traefik Dashboard', type: 'http', url: 'https://traefik.elate.me' },
    { name: 'Dev Environment', type: 'http', url: 'https://dev.elate.me' },
    { name: 'HomeLab Environment', type: 'http', url: 'https://homelab.elate.me' },
    { name: 'Uptime Kuma', type: 'http', url: 'https://uptime.elate.me' },

    // Internal services (HTTP)
    { name: 'Prometheus Server', type: 'http', url: 'http://prometheus-server.monitoring.svc.cluster.local' },
    { name: 'Alertmanager', type: 'http', url: 'http://prometheus-alertmanager.monitoring.svc.cluster.local:9093' }
];

function setupMonitors() {
    console.log('Setting up monitors for homelab services...\n');

    // Build a set of existing monitor names for quick lookup
    const existingNames = new Set(
        Object.values(existingMonitors).map(m => m.name)
    );

    console.log(`Found ${existingNames.size} existing monitors\n`);

    let completed = 0;
    let created = 0;
    let skipped = 0;
    const total = monitors.length;

    monitors.forEach((monitor, index) => {
        // Check if monitor already exists
        if (existingNames.has(monitor.name)) {
            console.log(`Skipping: "${monitor.name}" (already exists)`);
            skipped++;
            completed++;
            if (completed === total) {
                finishSetup(created, skipped);
            }
            return;
        }

        const monitorData = {
            type: monitor.type,
            name: monitor.name,
            url: monitor.url,
            interval: 60,
            retryInterval: 60,
            maxretries: 3,
            notificationIDList: {},
            ignoreTls: true,
            upsideDown: false,
            maxredirects: 10,
            accepted_statuscodes: ['200-299'],
            dns_resolve_type: 'A',
            dns_resolve_server: '1.1.1.1',
            proxyId: null,
            method: 'GET',
            body: null,
            headers: null,
            authMethod: null,
            active: true
        };

        console.log(`Creating: "${monitor.name}" (${monitor.url})`);

        socket.emit('add', monitorData, (res) => {
            if (res.ok) {
                console.log(`  Created successfully (ID: ${res.monitorID})`);
                created++;
            } else {
                console.log(`  Failed: ${res.msg || 'Unknown error'}`);
            }

            completed++;
            if (completed === total) {
                finishSetup(created, skipped);
            }
        });
    });
}

function finishSetup(created, skipped) {
    console.log('\n=========================================');
    console.log('Setup Complete!');
    console.log('=========================================');
    console.log(`Created: ${created} monitors`);
    console.log(`Skipped: ${skipped} monitors (already existed)`);
    console.log(`\nVisit ${UPTIME_KUMA_URL} to view your monitoring dashboard.\n`);

    socket.disconnect();
    process.exit(0);
}

// Handle timeout
setTimeout(() => {
    console.error('\nERROR: Setup timed out after 30 seconds');
    process.exit(1);
}, 30000);
