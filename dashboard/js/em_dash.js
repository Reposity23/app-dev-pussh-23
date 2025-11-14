const API_BASE_URL = window.location.origin + '/api';
const WS_URL = window.location.origin.replace('http', 'ws') + '/ws';

let socket = null;
let orders = [];
let currentEmployee = 'John Marwin';

document.addEventListener('DOMContentLoaded', () => {
    const employeeSelect = document.getElementById('employeeSelect');
    
    const savedEmployee = localStorage.getItem('currentEmployee');
    if (savedEmployee) {
        currentEmployee = savedEmployee;
        employeeSelect.value = currentEmployee;
    }
    
    employeeSelect.addEventListener('change', (e) => {
        currentEmployee = e.target.value;
        localStorage.setItem('currentEmployee', currentEmployee);
        updateDashboard();
    });
    
    initializeDashboard();
});

function initializeDashboard() {
    fetchOrders();
    connectWebSocket();
}

async function fetchOrders() {
    try {
        const response = await fetch(`${API_BASE_URL}/orders`);
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        orders = await response.json();
        updateDashboard();
    } catch (error) {
        console.error('Failed to fetch orders:', error);
        orders = [];
        updateDashboard();
    }
}

function connectWebSocket() {
    try {
        socket = new WebSocket(WS_URL);
        
        socket.onopen = () => {
            console.log('WebSocket connected');
            updateConnectionStatus(true);
        };
        
        socket.onmessage = (event) => {
            if (!event.data) return;
            
            try {
                const message = JSON.parse(event.data);
                
                if (message.type === 'clear') {
                    orders = [];
                    updateDashboard();
                    return;
                }
                
                updateOrAddOrder(message);
                updateDashboard();
            } catch (error) {
                console.error('Error parsing WebSocket message:', error);
            }
        };
        
        socket.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
        
        socket.onclose = () => {
            console.log('WebSocket disconnected');
            updateConnectionStatus(false);
            setTimeout(connectWebSocket, 5000);
        };
    } catch (error) {
        console.error('Error connecting WebSocket:', error);
        setTimeout(connectWebSocket, 5000);
    }
}

function updateOrAddOrder(order) {
    const index = orders.findIndex(o => o.id === order.id);
    if (index >= 0) {
        orders[index] = order;
    } else {
        orders.unshift(order);
    }
}

function updateDashboard() {
    document.getElementById('employeeName').textContent = currentEmployee;
    
    const employeeOrders = orders.filter(o => o.assigned_person === currentEmployee);
    
    const pendingOrders = employeeOrders.filter(o => 
        o.status === 'PENDING' || o.status === 'CANCEL'
    );
    
    const processedOrders = employeeOrders.filter(o => 
        o.status === 'DELIVERED' || o.status === 'RETURNED' || o.status === 'ON_THE_WAY'
    );
    
    const returnedOrders = employeeOrders.filter(o => o.status === 'RETURNED');
    
    let totalRevenue = 0;
    employeeOrders.forEach(order => {
        if (order.status === 'DELIVERED' || order.status === 'COMPLETED') {
            totalRevenue += order.total_amount;
        } else if (order.status === 'RETURNED') {
            totalRevenue -= order.total_amount;
        }
    });
    
    document.getElementById('totalRevenue').textContent = `₱${totalRevenue.toFixed(2)}`;
    document.getElementById('pendingCount').textContent = pendingOrders.length;
    document.getElementById('processedCount').textContent = processedOrders.length;
    document.getElementById('returnedCount').textContent = returnedOrders.length;
    
    renderPendingOrders(pendingOrders);
    renderProcessedOrders(processedOrders);
}

function renderPendingOrders(pendingOrders) {
    const tbody = document.getElementById('pendingOrdersBody');
    
    if (pendingOrders.length === 0) {
        tbody.innerHTML = `
            <tr>
                <td colspan="3" class="empty-state">
                    <p>No pending orders</p>
                </td>
            </tr>
        `;
        return;
    }
    
    tbody.innerHTML = pendingOrders.map(order => `
        <tr>
            <td>${order.toy_name}</td>
            <td>
                <span class="status-badge status-${order.status.toLowerCase()}">
                    ${order.status}
                </span>
            </td>
            <td>₱${order.total_amount.toFixed(2)}</td>
        </tr>
    `).join('');
}

function renderProcessedOrders(processedOrders) {
    const tbody = document.getElementById('processedOrdersBody');
    
    if (processedOrders.length === 0) {
        tbody.innerHTML = `
            <tr>
                <td colspan="3" class="empty-state">
                    <p>No processed orders</p>
                </td>
            </tr>
        `;
        return;
    }
    
    tbody.innerHTML = processedOrders.map(order => `
        <tr>
            <td>${order.toy_name}</td>
            <td>
                <span class="status-badge status-${order.status.toLowerCase().replace(/_/g, '-')}">
                    ${order.status}
                </span>
            </td>
            <td>₱${order.total_amount.toFixed(2)}</td>
        </tr>
    `).join('');
}

function updateConnectionStatus(connected) {
    const statusEl = document.getElementById('connectionStatus');
    statusEl.className = `connection-status ${connected ? 'connected' : 'disconnected'}`;
    statusEl.innerHTML = `
        <div class="status-indicator"></div>
        <span>${connected ? 'Connected' : 'Disconnected'}</span>
    `;
}
