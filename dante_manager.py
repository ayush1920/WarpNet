from flask import Flask,  request, render_template, redirect, url_for, session, make_response
from werkzeug.security import generate_password_hash, check_password_hash
import subprocess
import os
from datetime import timedelta

app = Flask(__name__)

CONFIG_DIR = "/etc/danted-warp"
PROXY_COUNT = len(list(filter(lambda x: x.startswith("warpns"), os.listdir(CONFIG_DIR))))
CONFIG_FILE = os.path.join(os.path.dirname(__file__), 'warp_manager.conf')
SECRET_KEY_FILE = os.path.join(os.path.dirname(__file__), 'flask_secret_key.txt')

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

# Utility to get base port from cnfig file
def get_base_port():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                if line.startswith('BASE_PORT='):
                    return int(line.strip().split('=')[1])

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5010)