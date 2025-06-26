// Add icon paths
const icons = {
  active: {
    16: "icon16_active.png",
    32: "icon32_active.png",
    128: "icon128_active.png",
    256: "icon256_active.png"
  },
  inactive: {
    16: "icon16.png",
    32: "icon32.png",
    128: "icon128.png",
    256: "icon256.png"
  }
};

// Check proxy status on startup
chrome.runtime.onStartup.addListener(() => {
  checkProxyStatus();
});

// Also check when extension is installed/updated
chrome.runtime.onInstalled.addListener(() => {
  checkProxyStatus();
});

function checkProxyStatus() {
  chrome.proxy.settings.get({}, (config) => {
    const proxyEnabled = config && config.value && config.value.mode === "fixed_servers";
    setIcon(proxyEnabled ? 'active' : 'inactive');
  });
}

function setIcon(status) {
  chrome.action.setIcon({ path: icons[status] });
}

// Listen for messages from popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'getCookies' && message.url) {
    chrome.cookies.getAll({ url: message.url }, (cookies) => {
      const sessionCookie = cookies.map(c => `${c.name}=${c.value}`).join('; ');
      sendResponse(sessionCookie);
    });
    // Return true to indicate async response
    return true;
  }
  
  if (message.type === 'proxyStatus') {
    setIcon(message.status);
  }
});

chrome.action.onClicked.addListener(() => {
  chrome.tabs.create({ url: chrome.runtime.getURL("popup.html") });
});
