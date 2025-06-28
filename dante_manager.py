import os
import io
import json
import shutil
import zipfile
import requests
import tempfile
import subprocess

from datetime import timedelta
from werkzeug.security import generate_password_hash, check_password_hash
from flask import Flask,  request, render_template, redirect, url_for, session, make_response, send_file, jsonify

app = Flask(__name__)

CONFIG_DIR = "/etc/danted-warp"
PROXY_COUNT = len(list(filter(lambda x: x.startswith("warpns"), os.listdir(CONFIG_DIR))))
CONFIG_FILE = os.path.join(os.path.dirname(__file__), 'warp_manager.conf')
SECRET_KEY_FILE = os.path.join(os.path.dirname(__file__), 'flask_secret_key.txt')
PUBLIC_IP = requests.get('https://api.ipify.org').text

# Load Flask secret key from file if available
if os.path.exists(SECRET_KEY_FILE):
    with open(SECRET_KEY_FILE) as f:
        app.secret_key = f.read().strip()
else:
    app.secret_key = os.environ.get('WARP_UI_SECRET', 'change_this_secret')

app.permanent_session_lifetime = timedelta(days=14)  # Set session lifetime to 14 days

# --- Authentication ---
PASS_FILE = os.path.join(os.path.dirname(__file__), 'ui_pass.txt')

def set_ui_password(password):
    with open(PASS_FILE, 'w') as f:
        f.write(generate_password_hash(password))

def check_ui_password(password):
    if not os.path.exists(PASS_FILE):
        return False
    with open(PASS_FILE) as f:
        hash = f.read().strip()
    return check_password_hash(hash, password)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        password = request.form.get('password', '')
        if check_ui_password(password):
            session['logged_in'] = True
            resp = make_response(redirect(url_for('index')))
            # Set cookie attributes for extension access
            resp.set_cookie(
                'session', request.cookies.get('session', ''), 
                httponly=False,  # Allow JS/extension access
                samesite=None, # Or 'None' if using HTTPS
                secure=False    # Set to True if using HTTPS
            )
            return resp
        else:
            return render_template('login.html', error='Invalid password')
    return render_template('login.html')

@app.before_request
def require_login():
    if request.endpoint not in ('login', 'logout', 'static') and not session.get('logged_in'):
        return redirect(url_for('login'))

def get_ip(i):
    return f"10.10.{i}.2"

def get_ns(i):
    return f"warpns{i}"

def get_conf(i):
    return f"{CONFIG_DIR}/warpns{i}.conf"

def get_port(i):
    return get_base_port() + i - 1

def supervisorctl(*command, shell=False):
    try:
        if shell:
            command = 'sudo supervisorctl ' + ' '.join(command)
        else:
            command = ['sudo', 'supervisorctl', *command]
        result = subprocess.run(command,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=40, shell=shell
        )
        return result.stdout.strip() + result.stderr.strip()
    except Exception as e:
        return str(e)

@app.route('/start/<int:i>', methods=['POST'])
def start_proxy(i):
    ns = get_ns(i)
    output = supervisorctl("start", f"{ns}-danted")
    if "ERROR" in output:
        return {"status": "error", "namespace": ns, "result": output}, 500

    output = supervisorctl("start", f"{ns}-socat")
    if "ERROR" in output:
        return {"status": "error", "namespace": ns, "result": output}, 500       
              
    return {"status": "started", "namespace": ns, "result": output}, 200

@app.route('/stop/<int:i>', methods=['POST'])
def stop_proxy(i):
    ns = get_ns(i)
    output = supervisorctl("stop", f"{ns}-danted")
    if "ERROR" in output:
        return {"status": "error", "namespace": ns, "result": output}, 500

    output = supervisorctl("stop", f"{ns}-socat")
    if "ERROR" in output:
        return {"status": "error", "namespace": ns, "result": output}, 500       
              
    return {"status": "stopped", "namespace": ns, "result": output}, 200

@app.route('/restart/<int:i>', methods=['POST'])
def restart_proxy(i):
    ns = get_ns(i)
    output = supervisorctl("restart", f"{ns}-danted")
    if "ERROR" in output:
        return {"status": "error", "namespace": ns, "result": output}, 500

    output = supervisorctl("restart", f"{ns}-socat")
    if "ERROR" in output:
        return {"status": "error", "namespace": ns, "result": output}, 500

    return {"status": "restarted", "namespace": ns, "result": output}, 200


@app.route('/start_all', methods=['POST'])
def start_all():
    output = supervisorctl("status | awk '{print $1}' | grep '^warpns'| xargs -r supervisorctl start", shell=True)
    return {'status': 'started', 'result': output}

@app.route('/stop_all', methods=['POST'])
def stop_all():
    output = supervisorctl("status | grep '^warpns' | awk '{print $1}' | xargs -r supervisorctl stop", shell=True)

    return {'status': 'stopped', 'result': output}

@app.route('/status', methods=['GET'])
def status():
    # Query supervisor for status of all proxies
    count = PROXY_COUNT
    status_dict = {}
    output = supervisorctl("status")
    output = output.splitlines()

    for i in range(1, count + 1):
        ns = get_ns(i)
        filtered_lines = [line for line in output if line.startswith(f'{ns}-')]
        
        # get actual status
        danted_conf = [line for line in filtered_lines if line.startswith(f'{ns}-danted')]
        if not danted_conf:
            status_dict[ns] = "Not Configured"
            continue

        is_running = all('RUNNING' in line.upper() for line in filtered_lines)
        if is_running:
            status_dict[ns] = "Running"
            continue

        danted_status = danted_conf[0].split()[1]
        status_dict[ns] = danted_status.strip().capitalize()

    return status_dict

@app.route('/extenstion/active_proxies', methods=['GET'])
def active_proxies():
    # Get the status of all proxies
    count = PROXY_COUNT
    base_port = get_base_port()
    
    status_dict = {}
    output = supervisorctl("status")
    output = output.splitlines()
    
    active_proxies = []
    
    for i in range(1, count + 1):
        ns = get_ns(i)
        port = base_port + i - 1
        filtered_lines = [line for line in output if line.startswith(f'{ns}-')]
        
        if filtered_lines and all('RUNNING' in line.upper() for line in filtered_lines):
            active_proxies.append({
                'name': ns,
                'port': port,
                'status': 'Running'
            })
    
    return {'active_proxies': active_proxies}

@app.route('/proxy_count')
def proxy_count():
    return {"count": PROXY_COUNT}

@app.route('/base_port')
def base_port():
    return {'base_port': get_base_port()}

@app.route('/')
def index():
    return render_template("dante_manager.html", proxy_count=PROXY_COUNT)

@app.route('/supervisor/<action>/<int:i>', methods=['POST'])
def supervisor_action(action, i):
    name = get_ns(i)
    output = supervisorctl(action, name)
    return {"result": output}

@app.route('/logout')
def logout():
    session.clear()  # Clear all session data
    return redirect(url_for('login'))

@app.route('/generate_batch', methods=['POST'])
def generate_batch():
    """Generate a batch file for launching Chrome with multiple profiles and proxies"""

    data = request.json
    if not data:
        return jsonify({"error": "No data provided"}), 400
    

    urls = data.get('urls', [])
    proxy_settings = data.get('proxySettings', [])
    
    if not urls or len(urls) != len(proxy_settings):
        return jsonify({"error": "Invalid data format"}), 400
    
    # Create temp directory for extensions
    temp_dir = tempfile.mkdtemp(prefix="chrome_extensions_")
    extensions_dir = os.path.join(temp_dir, "extensions")
    
    # delete any existing extensions in the directory
    if os.path.exists(extensions_dir):
        shutil.rmtree(extensions_dir)

    os.makedirs(extensions_dir, exist_ok=True)

    # Template directory path
    template_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'proxy_overlay_extension')
    
    # Create an extension for each proxy
    extension_paths = []
    for i, proxy_port in enumerate(proxy_settings):
        # Create extension directory
        ext_dir = os.path.join(extensions_dir, f"proxy-extension-{i+1}")
        
        # Copy template directory content
        shutil.copytree(template_dir, ext_dir)
        
        # Create config.json with proxy settings
        with open(os.path.join(ext_dir, "config.json"), "w") as f:
            json.dump({
                "ip": PUBLIC_IP, 
                "port": proxy_port
            }, f)
        
        extension_paths.append(ext_dir)
    
    
    # Create batch content
    batch_content = '@echo off\r\n'
    batch_content += 'set "SCRIPT_DIR=%~dp0"\r\n'
    batch_content += 'echo Starting Chrome profiles...\r\n'
    batch_content += f'mkdir ".\\extensions" 2>nul\r\n\r\n'
    
    # Copy extensions to a location that will be accessible from the batch file
    batch_content += 'echo Setting up extensions...\r\n'
    

        
    for i, (url, proxy_port) in enumerate(zip(urls, proxy_settings)):
        profile_name = f"profile{i + 1}"
        ext_path = f"extensions\\proxy-extension-{i+1}"
        
        batch_content += f'echo Starting Chrome for {url}...\r\n'
        batch_content += f'mkdir "{profile_name}" 2>nul\r\n'
        batch_content += f'start chrome --user-data-dir="%SCRIPT_DIR%{profile_name}" --proxy-server="socks5://{PUBLIC_IP}:{proxy_port}" --disable-features=DisableLoadExtensionCommandLineSwitch --load-extension="%SCRIPT_DIR%{ext_path}" --new-window "{url}"\r\n\r\n'

    batch_content += 'echo All Chrome profiles have been launched\r\n'
    batch_content += 'pause\r\n'
    

    zip_buffer = io.BytesIO()

    with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zipf:
    # Add folder contents
        for root, dirs, files in os.walk(extensions_dir):
            for file in files:
                full_path = os.path.join(root, file)
                arcname =  os.path.join('extensions', os.path.relpath(full_path, start=extensions_dir))
                zipf.write(full_path, arcname)

        # Add in-memory file
        mem_file = io.BytesIO(bytes(batch_content, 'utf-8'))
        zipf.writestr('start_chrome.bat', mem_file.getvalue())


    # Save the zip file to a temporary location
    zip_buffer.seek(0)

    # Write to temp file
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    tmp.write(zip_buffer.read())
    tmp.close()

    response = send_file(
        tmp.name, 
        as_attachment=True,
        download_name='bundle.zip',
        mimetype='application/zip'
    )
    
    # Ensure proper Content-Disposition header
    response.headers['Content-Disposition'] = 'attachment; filename=bundle.zip'
    
    return response


@app.route('/chrome_manager')
def chrome_manager():
    return render_template("chrome_manager.html")

# Utility to get base port from cnfig file
def get_base_port():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                if line.startswith('BASE_PORT='):
                    return int(line.strip().split('=')[1])


@app.after_request
def cleanup_temp_file(response):
    # Cleanup zip file if exists
    if response.direct_passthrough and response.status_code == 200:
        try:
            os.remove(response.direct_passthrough.name)
        except Exception:
            pass
    return response

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5010)