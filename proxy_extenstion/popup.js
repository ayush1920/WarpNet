const stepServer = document.getElementById('step-server');
const stepLogin = document.getElementById('step-login');
const stepProxy = document.getElementById('step-proxy');
const serverInput = document.getElementById('server');
const saveServerBtn = document.getElementById('save-server');
const loginBtn = document.getElementById('login-btn');
const passwordInput = document.getElementById('password');
const loginStatus = document.getElementById('login-status');
let proxyListDiv = document.getElementById('proxy-list');
const clearProxyBtn = document.getElementById('clear-proxy');
const proxyStatus = document.getElementById('proxy-status');
const serverLoadingOverlay = document.getElementById('server-loading');
const loginLoadingOverlay = document.getElementById('login-loading');
const proxyLoadingOverlay = document.getElementById('proxy-loading');

let server = '';
let globalHost = ''
let sessionCookie = '';
let proxies = [];
let selectedProxy = null;
let refreshInterval = null;

function showStep(step) {
  // First hide all steps
  stepServer.classList.add('hidden');
  stepLogin.classList.add('hidden');
  stepProxy.classList.add('hidden');

  // Then show the requested step
  step.classList.remove('hidden');
}

// Show loading during startup
document.addEventListener('DOMContentLoaded', () => {

  chrome.storage.local.get(['warpnest_server', 'warpnest_cookie'], (data) => {
    if (serverLoadingOverlay) serverLoadingOverlay.classList.remove('hidden');

    if (data.warpnest_server) {
      serverInput.value = data.warpnest_server;
      server = data.warpnest_server;
      globalHost = server.replace(/^https?:\/\//, '').replace(/\/$/, '').split(':')[0];
      console.log('Global host:', globalHost);

      if (data.warpnest_cookie) {
        // if (proxyLoadingOverlay) proxyLoadingOverlay.classList.remove('hidden');
        chrome.storage.local.get('warpnest_selected_proxy_name', (d) => {
          if (d.warpnest_selected_proxy_name) {
            console.log('Selected proxy name:', d.warpnest_selected_proxy_name);
            // load proxy form local storage
            loadProxyFromLocalStorage();
            showStep(stepProxy);
            if (proxyLoadingOverlay)
              proxyLoadingOverlay.classList.remove('hidden');
            clearProxyBtn.classList.remove('hidden');
          }
          else {
            clearProxyBtn.classList.add('hidden');
            if (loginLoadingOverlay)
              loginLoadingOverlay.classList.add('hidden');
            fetchProxies();
          }
        });
      }
    } else {
      // No cookie found, show login step
      if (serverLoadingOverlay) serverLoadingOverlay.classList.add('hidden');
      showStep(stepServer);
    }
  });
});

function loadProxyFromLocalStorage() {
  chrome.storage.local.get(['warpnest_proxies', 'warpnest_selected_proxy_name'], (data) => {
    proxies = data.warpnest_proxies || [];
    proxies = proxies.map(p => {
      return {
        ...p,
        host: globalHost, // Ensure host is set to globalHost
      };
    });
    renderProxyList();
  });
}

function saveServer() {
  server = serverInput.value.trim().replace(/\/+$/, '');
  if (!/^https?:\/\/[^ ]+/.test(server)) {
    alert('Please enter a valid server address (http://...)');
    return;
  }
  globalHost = server.replace(/^https?:\/\//, '').replace(/\/$/, '');

  // Show loading overlay when saving server
  //   if (serverLoadingOverlay) serverLoadingOverlay.classList.remove('hidden');


  chrome.storage.local.set({ warpnest_server: server }, () => {
    // Hide server loading, show login step
    if (loginLoadingOverlay) loginLoadingOverlay.classList.add('hidden');
    showStep(stepLogin);
  });
}

function login() {
  loginStatus.textContent = '';
  const password = passwordInput.value;
  console.log('warpnest_server:', server);

  fetch(server + '/login', {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'password=' + encodeURIComponent(password)
  }).then(resp => {
    if (resp.redirected || resp.url.endsWith('/')) {
      // Debug: check Set-Cookie header in response
      resp.headers.forEach((v, k) => {
        if (k.toLowerCase() === 'set-cookie') {
          console.log('Set-Cookie header:', v);
        }
      });
      chrome.runtime.sendMessage(
        { type: 'getCookies', url: server },
        (sessionCookie) => {
          if (sessionCookie) {
            chrome.storage.local.set({ warpnest_cookie: sessionCookie }, () => {
              return fetchProxies();
            });
          } else {

            loginStatus.textContent = 'Login succeeded, but no session cookie found. ' +
              'Check that the cookie domain matches the server address and that SameSite/Secure attributes allow access from extensions.';
          }
        }
      );
    } else {
      console.log('no session cookie found');
      loginStatus.textContent = 'Invalid password';
    }
  }).catch(() => {
    loginStatus.textContent = 'Could not connect to server';
  });
  loginStatus.classList.add('visible');
}

// Fetch proxies from /extenstion/active_proxies and update storage/UI
function fetchProxiesAndUpdateStorage(background = false) {
  chrome.storage.local.get(['warpnest_server', 'warpnest_cookie', 'warpnest_selected_proxy_name', 'warpnest_proxies'], (data) => {
    server = data.warpnest_server;
    sessionCookie = data.warpnest_cookie || '';
    const selectedProxyName = data.warpnest_selected_proxy_name;
    let connectedProxy = null;
    if (selectedProxyName && data.warpnest_proxies) {
      connectedProxy = data.warpnest_proxies.find(p => p.name === selectedProxyName);
    }
    fetch(server + '/extenstion/active_proxies', { credentials: 'include' })
      .then(r => r.json())
      .then(result => {
        let fetchedProxies = result.active_proxies || [];
        // Always keep the connected proxy in the list
        if (connectedProxy && !fetchedProxies.some(p => p.name === connectedProxy.name)) {
          fetchedProxies.push(connectedProxy);
        }
        proxies = fetchedProxies;
        chrome.storage.local.set({ warpnest_proxies: proxies });
        renderProxyList();
        showStep(stepProxy);
        if (!background && proxyLoadingOverlay) proxyLoadingOverlay.classList.add('hidden');
      })
      .catch(() => {
        // On error, use last known proxies from storage
        chrome.storage.local.get(['warpnest_proxies'], (d) => {
          proxies = d.warpnest_proxies || [];
          // Always keep the connected proxy in the list
          if (connectedProxy && !proxies.some(p => p.name === connectedProxy.name)) {
            proxies.push(connectedProxy);
          }
          renderProxyList();
          showStep(stepProxy);
          if (!background && proxyLoadingOverlay) proxyLoadingOverlay.classList.add('hidden');

          // Only show the cached message if this is not a background refresh
          if (!background) {
            updateStatus(proxyStatus, 'Using cached proxy list. You can still disconnect.', false);
          }
        });
      });
  });
}


// Overwrite fetchProxies to use the new logic
function fetchProxies() {
  if (proxyLoadingOverlay) proxyLoadingOverlay.classList.remove('hidden');
  fetchProxiesAndUpdateStorage(false);
}

// Update renderProxyList to start/stop background refresh
function renderProxyList() {
  // Remove any previous click handlers by replacing the node
  const newProxyListDiv = proxyListDiv.cloneNode(false);
  proxyListDiv.parentNode.replaceChild(newProxyListDiv, proxyListDiv);
  proxyListDiv = newProxyListDiv;

  // add globalHost to each proxy
  proxies = proxies.map(p => {
    return {
      ...p, host: globalHost,
    }
  });
  proxies.forEach((p, idx) => {
    const div = document.createElement('div');
    div.className = 'proxy-item';
    div.dataset.index = idx;
    div.innerHTML = `
      <label class="custom-radio">
        <input type="radio" class="proxy-radio" name="proxy" id="proxy${idx}" value="${idx}">
        <span class="checkmark"></span>
        <div class="proxy-info">
          <div class="proxy-name">${p.name}</div>
          <div class="proxy-address">${p.host}:${p.port}</div>
        </div>
      </label>
    `;
    newProxyListDiv.appendChild(div);
    div.addEventListener('click', (e) => {
      e.stopPropagation();
      const index = parseInt(div.dataset.index);
      if (isNaN(index) || index < 0 || index >= proxies.length) return;
      selectedProxy = proxies[index];
      const radio = div.querySelector('.proxy-radio');
      if (radio) radio.checked = true;
      document.querySelectorAll('.proxy-item').forEach(item => item.classList.remove('active'));
      div.classList.add('active');
      setProxy();
      chrome.storage.local.set({ warpnest_selected_proxy_name: selectedProxy.name });
    });
  });

  chrome.storage.local.get(['warpnest_selected_proxy_name'], (data) => {
    if (data.warpnest_selected_proxy_name) {
      const proxyIndex = proxies.findIndex(p => p.name === data.warpnest_selected_proxy_name);
      if (proxyIndex !== -1) {
        const radio = document.getElementById(`proxy${proxyIndex}`);
        if (radio) {
          radio.checked = true;
          selectedProxy = proxies[proxyIndex];
          const item = radio.closest('.proxy-item');
          if (item) {
            item.classList.add('active');
          }
        }
      }
    }
    if (proxyLoadingOverlay) proxyLoadingOverlay.classList.add('hidden');
  });
}


// Update status display functions
function updateStatus(element, message, isSuccess = false) {
  element.textContent = message;
  element.className = 'status' + (isSuccess ? ' success' : '') + ' visible';
}

function setProxy() {
  if (!selectedProxy) {
    updateStatus(proxyStatus, 'Please select a proxy');
    return;
  }
  const config = {
    mode: "fixed_servers",
    rules: {
      singleProxy: {
        scheme: "socks5",
        host: selectedProxy.host,
        port: selectedProxy.port
      },
      bypassList: ["<local>"]
    }
  };
  console.log(config)

  chrome.proxy.settings.set({ value: config, scope: 'regular' }, () => {
    updateStatus(proxyStatus, 'Connected to: ' + selectedProxy.name, true);

    // Send message to background script to update icon to 'active'
    chrome.runtime.sendMessage({ type: 'proxyStatus', status: 'active' });

    // Save selected proxy name to storage
    console.log('Selected proxy name:', selectedProxy.name);
    clearProxyBtn.classList.remove('hidden');
    chrome.storage.local.set({ warpnest_selected_proxy_name: selectedProxy.name }, () => {
      // Auto close popup after a short delay
      setTimeout(() => window.close(), 800);
    });
  });
}

function clearProxy() {
  chrome.proxy.settings.clear({}, () => {
    selectedProxy = null;

    // Send message to background script to update icon to 'inactive'
    chrome.runtime.sendMessage({ type: 'proxyStatus', status: 'inactive' });

    // Remove selected proxy name and stop background refresh
    chrome.storage.local.remove('warpnest_selected_proxy_name', () => {
      updateStatus(proxyStatus, 'Disconnected from proxy');
      renderProxyList();
      clearProxyBtn.classList.add('hidden');
      // Auto close popup after a short delay
      setTimeout(() => window.close(), 800);
    });
  });
}

// Add signout functionality to clear all session data
function signOut() {
  // Show loading while signing out
  if (proxyLoadingOverlay) proxyLoadingOverlay.classList.remove('hidden');

  // Clear proxy settings first
  chrome.proxy.settings.clear({}, () => {
    // Send message to background script to update icon to 'inactive'
    chrome.runtime.sendMessage({ type: 'proxyStatus', status: 'inactive' });


    // Then remove all stored data
    chrome.storage.local.remove(['warpnest_server', 'warpnest_cookie', 'warpnest_selected_proxy_name', 'warpnest_proxies'], () => {
      // Reset UI state
      serverInput.value = '';
      passwordInput.value = '';
      loginStatus.textContent = '';
      proxyStatus.textContent = '';
      server = '';
      sessionCookie = '';
      proxies = [];
      selectedProxy = null;

      // Hide loading and show server input step
      if (proxyLoadingOverlay) proxyLoadingOverlay.classList.add('hidden');
      showStep(stepServer);
    });
  });
}

saveServerBtn.onclick = saveServer;
loginBtn.onclick = login;
clearProxyBtn.onclick = clearProxy;

// Add signout button event listener
document.getElementById('signout-btn').addEventListener('click', signOut);

// Add event listener for the new "Web Portal" button
document.getElementById('open-webapp').addEventListener('click', () => {
  chrome.storage.local.get(['warpnest_server'], (data) => {
    if (data.warpnest_server) {
      chrome.tabs.create({ url: data.warpnest_server });
    }
  });
});
