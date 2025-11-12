#!/usr/bin/env python3
from flask import Flask, render_template, jsonify
import psutil
import subprocess
import os
from datetime import datetime

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/status')
def get_status():
    try:
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        net_io = psutil.net_io_counters()
        
        # 检查进程状态
        processes = {}
        for proc_name in ['java', 'frpc', 'supervisord']:
            processes[proc_name] = any(proc_name in p.name().lower() for p in psutil.process_iter(['name']))
        
        # 系统运行时间
        boot_time = datetime.fromtimestamp(psutil.boot_time())
        uptime = str(datetime.now() - boot_time).split('.')[0]
        
        return jsonify({
            'cpu': {
                'percent': cpu_percent,
                'count': psutil.cpu_count()
            },
            'memory': {
                'total': memory.total,
                'used': memory.used,
                'percent': memory.percent
            },
            'disk': {
                'total': disk.total,
                'used': disk.used,
                'percent': disk.percent
            },
            'network': {
                'sent': net_io.bytes_sent,
                'recv': net_io.bytes_recv
            },
            'processes': processes,
            'uptime': uptime,
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=7860, debug=False)
