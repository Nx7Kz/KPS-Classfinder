"""
สร้างรายงานผลตรวจ SonarQube เป็น PDF:  python sonar/sonar_report.py

ดึงผลตรวจล่าสุดผ่าน SonarQube Web API แล้วสร้างรายงานภาษาไทย:
  สรุปคะแนน (Quality Gate / เกรด A–E) · จำนวนปัญหาแยกประเภทและความรุนแรง
  · ไฟล์ที่มีปัญหามากที่สุด · รายการปัญหา · Security Hotspots
ได้ไฟล์ sonar/reports/sonar-report-<วันที่>.pdf (และ .html)

ต้องรัน sonar_scan.py มาก่อนอย่างน้อย 1 ครั้ง (ใช้รหัส admin จาก sonar/.env)
แปลงเป็น PDF ด้วย Chrome / Edge ที่มีในเครื่อง (ไม่ต้อง pip install อะไร)
"""
import html
import os
import subprocess
import sys
from collections import Counter
from datetime import datetime

# คอนโซลบางเครื่อง Windows ใช้ code page เก่า (cp1252/cp874) ที่พิมพ์ภาษาไทยไม่ได้ -> บังคับ UTF-8
if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')

from sonar_scan import HOST, PROJECT, HERE, load_env, api

REPORT_DIR = os.path.join(HERE, 'reports')
BROWSERS = [
    os.environ.get('CHROME_PATH', ''),
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    '/usr/bin/google-chrome', '/usr/bin/chromium',
]

TYPE_TH = {'BUG': 'Bug (ทำงานผิดได้)', 'VULNERABILITY': 'Vulnerability (ช่องโหว่)', 'CODE_SMELL': 'Code Smell (ดูแลยาก)'}
SEV_ORDER = ['BLOCKER', 'CRITICAL', 'MAJOR', 'MINOR', 'INFO']
SEV_TH = {'BLOCKER': 'ร้ายแรงมาก', 'CRITICAL': 'ร้ายแรง', 'MAJOR': 'สำคัญ', 'MINOR': 'เล็กน้อย', 'INFO': 'ข้อมูล'}
PROB_TH = {'HIGH': 'สูง', 'MEDIUM': 'กลาง', 'LOW': 'ต่ำ'}


def fetch_all(admin, path, key, params):
    """ดึงข้อมูลแบบแบ่งหน้าจนครบ"""
    out, page = [], 1
    while True:
        r = api('GET', path, admin, {**params, 'ps': 500, 'p': page})
        out += r.get(key, [])
        total = r.get('paging', {}).get('total', r.get('total', 0))
        if len(out) >= total or not r.get(key):
            return out
        page += 1


def grade(v):
    return 'ABCDE'[int(float(v)) - 1] if v else '-'


def build_html(admin):
    keys = ('bugs,vulnerabilities,security_hotspots,code_smells,duplicated_lines_density,ncloc,files,'
            'reliability_rating,security_rating,sqale_rating,security_review_rating,sqale_index,complexity,'
            'coverage,line_coverage,branch_coverage')
    m = api('GET', '/api/measures/component', admin, {'component': PROJECT, 'metricKeys': keys})
    v = {x['metric']: x.get('value') for x in m['component']['measures']}
    gate = api('GET', '/api/qualitygates/project_status', admin, {'projectKey': PROJECT})['projectStatus']
    analyses = api('GET', '/api/project_analyses/search', admin, {'project': PROJECT, 'ps': 1}).get('analyses', [])
    analyzed = analyses[0]['date'][:16].replace('T', ' ') if analyses else '-'

    issues = fetch_all(admin, '/api/issues/search', 'issues', {'componentKeys': PROJECT, 'resolved': 'false'})
    hotspots = fetch_all(admin, '/api/hotspots/search', 'hotspots', {'project': PROJECT, 'status': 'TO_REVIEW'})

    by_type = Counter(i['type'] for i in issues)
    by_sev = Counter(i['severity'] for i in issues)
    by_file = Counter(i['component'].split(':', 1)[-1] for i in issues)
    issues.sort(key=lambda i: (SEV_ORDER.index(i['severity']), i['component'], i.get('line', 0)))

    e = html.escape
    debt_h = round(int(v.get('sqale_index') or 0) / 60, 1)
    card = lambda label, value, sub='': f'<div class="card"><div class="lbl">{label}</div><div class="val">{value}</div><div class="sub">{sub}</div></div>'
    gate_ok = gate['status'] == 'OK'

    rows_issue = ''.join(
        f"<tr><td class='sev s-{i['severity']}'>{SEV_TH[i['severity']]}</td><td>{e(TYPE_TH.get(i['type'], i['type']).split(' ')[0])}</td>"
        f"<td class='mono'>{e(i['component'].split(':', 1)[-1])}{':' + str(i['line']) if i.get('line') else ''}</td>"
        f"<td>{e(i['message'])}</td><td class='mono small'>{e(i['rule'])}</td></tr>"
        for i in issues[:150])
    rows_hot = ''.join(
        f"<tr><td>{PROB_TH.get(h['vulnerabilityProbability'], h['vulnerabilityProbability'])}</td>"
        f"<td class='mono'>{e(h['component'].split(':', 1)[-1])}{':' + str(h['line']) if h.get('line') else ''}</td>"
        f"<td>{e(h['message'])}</td><td class='mono small'>{e(h['ruleKey'])}</td></tr>"
        for h in hotspots) or "<tr><td colspan='4' class='muted'>ไม่มีจุดที่ต้องตรวจทาน</td></tr>"
    rows_file = ''.join(f"<tr><td class='mono'>{e(f)}</td><td class='num'>{n}</td></tr>" for f, n in by_file.most_common(10))
    rows_type = ''.join(f"<tr><td>{TYPE_TH.get(t, t)}</td><td class='num'>{by_type.get(t, 0)}</td></tr>" for t in TYPE_TH)
    rows_sev = ''.join(f"<tr><td>{s} · {SEV_TH[s]}</td><td class='num'>{by_sev.get(s, 0)}</td></tr>" for s in SEV_ORDER)
    conds = ''.join(
        f"<tr><td>{e(c['metricKey'])}</td><td class='num'>{e(c.get('actualValue', '-'))}</td>"
        f"<td class='num'>{e(c.get('comparator', ''))} {e(c.get('errorThreshold', ''))}</td>"
        f"<td class='{'ok' if c['status'] == 'OK' else 'bad'}'>{c['status']}</td></tr>"
        for c in gate.get('conditions', [])) or "<tr><td colspan='4' class='muted'>ยังไม่มีเงื่อนไขที่ประเมิน (ประเมินกับโค้ดใหม่ตั้งแต่การตรวจครั้งถัดไป)</td></tr>"
    more = f"<p class='muted'>แสดง 150 จาก {len(issues)} รายการ — ดูทั้งหมดที่ {HOST}/project/issues?id={PROJECT}</p>" if len(issues) > 150 else ''

    return f"""<!doctype html><html lang="th"><head><meta charset="utf-8"><title>SonarQube Report</title>
<style>
  @page {{ size: A4; margin: 14mm 12mm; }}
  body {{ font-family: 'Leelawadee UI', 'Tahoma', sans-serif; color: #221b18; font-size: 10.5pt; margin: 0; }}
  h1 {{ font-size: 18pt; margin: 0 0 2px; }} h2 {{ font-size: 13pt; margin: 18px 0 6px; border-bottom: 2px solid #15803d; padding-bottom: 3px; }}
  .meta {{ color: #6f6460; font-size: 9.5pt; }}
  .gate {{ display: inline-block; margin-top: 8px; padding: 5px 14px; border-radius: 6px; font-weight: 700; color: #fff; background: {'#2e9e5b' if gate_ok else '#c7362f'}; }}
  .cards {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-top: 12px; }}
  .card {{ border: 1px solid #e3d8d1; border-radius: 8px; padding: 8px 10px; }}
  .lbl {{ font-size: 9pt; color: #6f6460; }} .val {{ font-size: 17pt; font-weight: 700; }} .sub {{ font-size: 8.5pt; color: #8a7d77; }}
  table {{ width: 100%; border-collapse: collapse; margin-top: 4px; }}
  th, td {{ border-bottom: 1px solid #ece3dd; padding: 4px 6px; text-align: left; vertical-align: top; }}
  th {{ background: #f7f2ee; font-size: 9.5pt; }}
  .num {{ text-align: right; }} .mono {{ font-family: Consolas, monospace; font-size: 8.5pt; word-break: break-all; }} .small {{ font-size: 8pt; color: #6f6460; }}
  .two {{ display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }}
  .sev {{ font-weight: 700; white-space: nowrap; }} .s-BLOCKER, .s-CRITICAL {{ color: #c7362f; }} .s-MAJOR {{ color: #b86b00; }} .s-MINOR, .s-INFO {{ color: #6f6460; }}
  .ok {{ color: #2e9e5b; font-weight: 700; }} .bad {{ color: #c7362f; font-weight: 700; }} .muted {{ color: #8a7d77; }}
  tr {{ page-break-inside: avoid; }}
</style></head><body>
<h1>รายงานคุณภาพโค้ด (SonarQube)</h1>
<div class="meta">โปรเจกต์: KPS ClassFinder (backend + แดชบอร์ด admin) · ตรวจเมื่อ {e(analyzed)} · สร้างรายงาน {datetime.now():%Y-%m-%d %H:%M}</div>
<div class="gate">Quality Gate: {'ผ่าน (OK)' if gate_ok else 'ไม่ผ่าน (' + gate['status'] + ')'}</div>

<div class="cards">
  {card('Bugs', v.get('bugs', '-'), 'Reliability ' + grade(v.get('reliability_rating')))}
  {card('Vulnerabilities', v.get('vulnerabilities', '-'), 'Security ' + grade(v.get('security_rating')))}
  {card('Security Hotspots', v.get('security_hotspots', '-'), 'Review ' + grade(v.get('security_review_rating')))}
  {card('Code Smells', v.get('code_smells', '-'), 'Maintainability ' + grade(v.get('sqale_rating')))}
  {card('บรรทัดโค้ด', v.get('ncloc', '-'), f"{v.get('files', '-')} ไฟล์")}
  {card('โค้ดซ้ำ', (v.get('duplicated_lines_density') or '0') + '%', 'ของบรรทัดทั้งหมด')}
  {card('Technical Debt', f'{debt_h} ชม.', 'เวลาที่ใช้แก้ Code Smells ทั้งหมด')}
  {card('Complexity', v.get('complexity', '-'), 'ความซับซ้อนรวม')}
  {card('Coverage', (v.get('coverage') or '-') + ('%' if v.get('coverage') else ''), 'ยังไม่มีชุดทดสอบอัตโนมัติ' if not v.get('coverage') else f"บรรทัด {v.get('line_coverage', '-')}% · เงื่อนไข {v.get('branch_coverage', '-')}%")}
</div>

<h2>เงื่อนไข Quality Gate</h2>
<table><tr><th>ตัวชี้วัด</th><th class="num">ค่าจริง</th><th class="num">เกณฑ์</th><th>ผล</th></tr>{conds}</table>

<div class="two">
  <div><h2>แยกตามประเภท</h2><table><tr><th>ประเภท</th><th class="num">จำนวน</th></tr>{rows_type}</table>
       <h2>แยกตามความรุนแรง</h2><table><tr><th>ความรุนแรง</th><th class="num">จำนวน</th></tr>{rows_sev}</table></div>
  <div><h2>ไฟล์ที่มีปัญหามากที่สุด</h2><table><tr><th>ไฟล์</th><th class="num">ปัญหา</th></tr>{rows_file}</table></div>
</div>

<h2>Security Hotspots ที่ต้องตรวจทาน ({len(hotspots)})</h2>
<table><tr><th>โอกาสเป็นช่องโหว่</th><th>ตำแหน่ง</th><th>รายละเอียด</th><th>กฎ</th></tr>{rows_hot}</table>

<h2>รายการปัญหา ({len(issues)})</h2>
<table><tr><th>ความรุนแรง</th><th>ประเภท</th><th>ตำแหน่ง</th><th>รายละเอียด</th><th>กฎ</th></tr>{rows_issue}</table>
{more}
</body></html>"""


def to_pdf(html_path, pdf_path):
    browser = next((b for b in BROWSERS if b and os.path.exists(b)), None)
    if not browser:
        print('  ไม่พบ Chrome / Edge — ได้แค่ไฟล์ HTML (เปิดแล้วสั่งพิมพ์เป็น PDF เองได้)')
        return False
    subprocess.run([browser, '--headless=new', '--disable-gpu', '--no-pdf-header-footer',
                    f'--print-to-pdf={pdf_path}', 'file:///' + html_path.replace('\\', '/')],
                   capture_output=True, timeout=120)
    return os.path.exists(pdf_path)


if __name__ == '__main__':
    env = load_env()
    if 'SONAR_ADMIN_PASSWORD' not in env:
        sys.exit('  ยังไม่ได้ตั้งค่า — รัน python sonar/sonar_scan.py ก่อน')
    admin = ('admin', env['SONAR_ADMIN_PASSWORD'])
    os.makedirs(REPORT_DIR, exist_ok=True)
    name = f'sonar-report-{datetime.now():%Y%m%d}'
    html_path = os.path.join(REPORT_DIR, name + '.html')
    pdf_path = os.path.join(REPORT_DIR, name + '.pdf')
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(build_html(admin))
    ok = to_pdf(html_path, pdf_path)
    print(f'\n  สร้างรายงานแล้ว\n    {pdf_path if ok else html_path}\n')
