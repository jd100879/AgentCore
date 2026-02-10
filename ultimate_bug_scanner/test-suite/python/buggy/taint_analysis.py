from flask import Flask, request
import sqlite3
import subprocess

app = Flask(__name__)
conn = sqlite3.connect(':memory:')

@app.route('/show')
def show_comment():
    comment = request.args.get('comment')  # taint source
    html = f"<div class='comment'>{comment}</div>"
    return html  # sent directly to client

def search_user():
    username = request.args['user']
    sql = "SELECT * FROM users WHERE username = '" + username + "'"
    return conn.execute(sql)

def run_ls():
    path = request.args.get('path', '.')
    cmd = f"ls {path}"
    subprocess.run(cmd, shell=True)

@app.route('/exec')
def run_code():
    payload = request.args.get('code')
    return str(eval(payload))
