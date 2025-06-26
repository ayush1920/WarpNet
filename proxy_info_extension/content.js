fetch(chrome.runtime.getURL("config.json"))
  .then(res => res.json())
  .then(data => {
    const badge = document.createElement("div");
    badge.textContent = `Proxy: ${data.ip}:${data.port}`;
    Object.assign(badge.style, {
      position: "fixed",
      top: "50px",
      left: "50%",
      transform: "translate(-50%, -50%)",
      background: "#000a",
      color: "#fff",
      padding: "5px 10px",
      fontSize: "20px",
      borderRadius: "10px",
      zIndex: 999999,
      fontFamily: "monospace",
      pointerEvents: "none",
      opacity: 1,
      border: "1px solid #fff",
      transition: "opacity 0.3s"
    });
    badge.addEventListener("mouseenter", () => badge.style.opacity = 1);
    badge.addEventListener("mouseleave", () => badge.style.opacity = 0.4);
    document.body.appendChild(badge);
  });
