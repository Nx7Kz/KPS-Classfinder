"""
ตรวจคุณภาพโค้ดด้วย SonarQube:  python sonar/sonar_scan.py

ครั้งแรกจะตั้งค่าให้อัตโนมัติ:
  - เปลี่ยนรหัสผ่าน admin จากค่าเริ่มต้น (admin/admin) เป็นรหัสสุ่ม
  - สร้างโปรเจกต์ + token สำหรับ scanner
  - บันทึกรหัส/token ไว้ใน sonar/.env (ไฟล์นี้ไม่ขึ้น git)
จากนั้นรัน sonar-scanner (ผ่าน Docker) รอผลตรวจ แล้วสรุปผลบนหน้าจอ

ต้องเปิด SonarQube ก่อน:  docker compose -f sonar/docker-compose.yml up -d
ใช้แค่ Python standard library ไม่ต้อง pip install อะไร

หมายเหตุ: backend ยังไม่มีชุดทดสอบอัตโนมัติ (สคริปต์ "test" ใน kps_backend/package.json เป็นแค่ placeholder)
จึงยังไม่มีการวัด coverage ส่งเข้า SonarQube ในตอนนี้ — ตรวจ Bug/Vulnerability/Code Smell ได้ตามปกติ
"""
import base64
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# คอนโซลบางเครื่อง Windows ใช้ code page เก่า (cp1252/cp874) ที่พิมพ์ภาษาไทยไม่ได้ -> บังคับ UTF-8
if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ENV_FILE = os.path.join(HERE, '.env')
HOST = os.environ.get('SONAR_HOST_URL', 'http://localhost:9000')
PROJECT = 'kps-classfinder'


def load_env():
    env = {}
    if os.path.exists(ENV_FILE):
        for line in open(ENV_FILE, encoding='utf-8'):
            if '=' in line and not line.lstrip().startswith('#'):
                k, v = line.strip().split('=', 1)
                env[k] = v
    return env


def save_env(env):
    with open(ENV_FILE, 'w', encoding='utf-8') as f:
        f.write('# สร้างโดย sonar_scan.py — ห้ามขึ้น git (มีรหัส admin และ token ของ SonarQube)\n')
        for k, v in env.items():
            f.write(f'{k}={v}\n')


def api(method, path, auth, params=None):
    """เรียก SonarQube Web API; auth = (user, password) หรือ token"""
    data = urllib.parse.urlencode(params or {}).encode() if method == 'POST' else None
    url = HOST + path + ('?' + urllib.parse.urlencode(params) if method == 'GET' and params else '')
    req = urllib.request.Request(url, data=data, method=method)
    cred = f'{auth[0]}:{auth[1]}' if isinstance(auth, tuple) else f'{auth}:'
    req.add_header('Authorization', 'Basic ' + base64.b64encode(cred.encode()).decode())
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read().decode()
        return json.loads(body) if body else {}


def wait_until_up(timeout=300):
    print(f'  รอ SonarQube ที่ {HOST} ...', end='', flush=True)
    end = time.time() + timeout
    while time.time() < end:
        try:
            with urllib.request.urlopen(HOST + '/api/system/status', timeout=5) as r:
                if json.loads(r.read())['status'] == 'UP':
                    print(' พร้อม')
                    return
        except (urllib.error.URLError, ConnectionError, TimeoutError, KeyError):
            pass
        print('.', end='', flush=True)
        time.sleep(5)
    sys.exit('\n  SonarQube ไม่พร้อม — เปิดด้วย: docker compose -f sonar/docker-compose.yml up -d')


GATE_NAME = 'KPS way (no test suite yet)'


def ensure_quality_gate(admin):
    """
    สร้าง Quality Gate ของโปรเจกต์นี้เอง แทน "Sonar way" เริ่มต้น: เงื่อนไขเหมือนกันทุกอย่าง
    (ห้ามมีปัญหาใหม่, โค้ดซ้ำใหม่ <3%, security hotspots ต้องตรวจทานครบ) ยกเว้น "coverage บนโค้ดใหม่ ≥80%"
    ที่ตัดออก เพราะ backend ยังไม่มีชุดทดสอบอัตโนมัติเลย (ดูเหตุผลใน sonar/README.md) — ตัดเงื่อนไขที่ยังทำไม่ได้จริง
    ออก ดีกว่าปล่อยให้ค้างสีแดงถาวรทั้งที่โค้ดไม่มีปัญหา เมื่อมีชุดทดสอบแล้วค่อยสลับโปรเจกต์นี้กลับไปใช้ "Sonar way" ได้

    หมายเหตุ: api/qualitygates/create สร้างเงื่อนไขมาตรฐาน 4 ข้อ (CAYC) ให้อัตโนมัติอยู่แล้ว รวม coverage ด้วย
    จึงแค่สร้างแล้วลบเฉพาะเงื่อนไข coverage ออก ไม่ต้องเพิ่มเงื่อนไขเองทีละอัน (ยิ่งเพิ่มเองจะชนกับของที่มีอยู่แล้ว)
    """
    gates = api('GET', '/api/qualitygates/list', admin).get('qualitygates', [])
    if not any(g['name'] == GATE_NAME for g in gates):
        api('POST', '/api/qualitygates/create', admin, {'name': GATE_NAME})
        conditions = api('GET', '/api/qualitygates/show', admin, {'name': GATE_NAME})['conditions']
        coverage = next((c for c in conditions if c['metric'] == 'new_coverage'), None)
        if coverage:
            api('POST', '/api/qualitygates/delete_condition', admin, {'id': coverage['id']})
        print(f'  สร้าง Quality Gate "{GATE_NAME}" แล้ว (ไม่มีเงื่อนไข coverage)')
    api('POST', '/api/qualitygates/select', admin, {'gateName': GATE_NAME, 'projectKey': PROJECT})


def first_time_setup(env):
    """เปลี่ยนรหัส admin, สร้างโปรเจกต์ และ token (ทำครั้งเดียว)"""
    if 'SONAR_ADMIN_PASSWORD' not in env:
        new_pw = secrets.token_urlsafe(18) + 'aA1!'
        api('POST', '/api/users/change_password', ('admin', 'admin'),
            {'login': 'admin', 'previousPassword': 'admin', 'password': new_pw})
        env['SONAR_ADMIN_PASSWORD'] = new_pw
        save_env(env)
        print('  ตั้งรหัสผ่าน admin ใหม่แล้ว (เก็บใน sonar/.env)')
    admin = ('admin', env['SONAR_ADMIN_PASSWORD'])

    found = api('GET', '/api/projects/search', admin, {'projects': PROJECT}).get('components', [])
    if not found:
        api('POST', '/api/projects/create', admin, {'project': PROJECT, 'name': 'KPS ClassFinder'})
        print(f'  สร้างโปรเจกต์ {PROJECT} แล้ว')
    ensure_quality_gate(admin)

    if 'SONAR_TOKEN' not in env:
        t = api('POST', '/api/user_tokens/generate', admin,
                {'name': f'scanner-{int(time.time())}', 'type': 'PROJECT_ANALYSIS_TOKEN', 'projectKey': PROJECT})
        env['SONAR_TOKEN'] = t['token']
        save_env(env)
        print('  สร้าง token สำหรับ scanner แล้ว (เก็บใน sonar/.env)')

    # webhook: SonarQube ส่งผลตรวจ (JSON) ไปที่ URL นี้ทุกครั้งที่ตรวจเสร็จ — ตั้งด้วย SONAR_WEBHOOK_URL
    hook_url = os.environ.get('SONAR_WEBHOOK_URL') or env.get('SONAR_WEBHOOK_URL')
    if hook_url:
        hooks = api('GET', '/api/webhooks/list', admin, {'project': PROJECT}).get('webhooks', [])
        if not any(h['url'] == hook_url for h in hooks):
            api('POST', '/api/webhooks/create', admin, {'project': PROJECT, 'name': 'report-hook', 'url': hook_url})
            print(f'  ตั้ง webhook -> {hook_url}')
    return admin


def run_scanner(token):
    """รัน sonar-scanner ผ่าน Docker (ไม่ต้องติดตั้ง Java / scanner ในเครื่อง)"""
    scanner_host = HOST.replace('localhost', 'host.docker.internal').replace('127.0.0.1', 'host.docker.internal')
    cmd = ['docker', 'run', '--rm',
           '-e', f'SONAR_HOST_URL={scanner_host}', '-e', f'SONAR_TOKEN={token}',
           '-v', f'{ROOT}:/usr/src', 'sonarsource/sonar-scanner-cli']
    print('  กำลังตรวจโค้ด (sonar-scanner) ...')
    p = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if p.returncode != 0:
        print(p.stdout[-3000:], p.stderr[-2000:])
        sys.exit('  sonar-scanner ล้มเหลว')
    task = next((l.split('id=')[-1].strip() for l in p.stdout.splitlines() if 'api/ce/task?id=' in l), None)
    return task


def wait_task(admin, task_id):
    print('  รอ SonarQube ประมวลผล ...', end='', flush=True)
    for _ in range(120):
        t = api('GET', '/api/ce/task', admin, {'id': task_id})['task']
        if t['status'] in ('SUCCESS', 'FAILED', 'CANCELED'):
            print(' ' + t['status'])
            return t['status']
        print('.', end='', flush=True)
        time.sleep(3)
    return 'TIMEOUT'


def summary(admin):
    keys = 'bugs,vulnerabilities,security_hotspots,code_smells,duplicated_lines_density,ncloc,' \
           'reliability_rating,security_rating,sqale_rating'
    m = api('GET', '/api/measures/component', admin, {'component': PROJECT, 'metricKeys': keys})
    vals = {x['metric']: x.get('value') for x in m['component']['measures']}
    gate = api('GET', '/api/qualitygates/project_status', admin, {'projectKey': PROJECT})['projectStatus']['status']
    grade = lambda v: 'ABCDE'[int(float(v)) - 1] if v else '-'
    print(f"""
  ผลตรวจ: Quality Gate = {gate}
    บรรทัดโค้ด           {vals.get('ncloc')}
    Bugs                 {vals.get('bugs')}   (Reliability {grade(vals.get('reliability_rating'))})
    Vulnerabilities      {vals.get('vulnerabilities')}   (Security {grade(vals.get('security_rating'))})
    Security Hotspots    {vals.get('security_hotspots')}
    Code Smells          {vals.get('code_smells')}   (Maintainability {grade(vals.get('sqale_rating'))})
    โค้ดซ้ำ              {vals.get('duplicated_lines_density')}%

  ดูรายละเอียด: {HOST}/dashboard?id={PROJECT}   (ล็อกอิน admin / รหัสใน sonar/.env)
  สร้างรายงาน PDF: python sonar/sonar_report.py
""")


if __name__ == '__main__':
    wait_until_up()
    env = load_env()
    admin = first_time_setup(env)
    task = run_scanner(env['SONAR_TOKEN'])
    if task and wait_task(admin, task) != 'SUCCESS':
        sys.exit('  ประมวลผลผลตรวจไม่สำเร็จ ดูที่ ' + HOST + '/admin/background_tasks')
    summary(admin)
