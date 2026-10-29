"""NODO local controller. Run: uvicorn core.app:app --host 0.0.0.0 --port 8080"""
import asyncio
import json
import os
import secrets
import sqlite3
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = Path(os.getenv('NODO_DB', ROOT / 'nodo.sqlite3'))
TOKEN = os.getenv('NODO_TOKEN', '').strip()
MQTT_HOST = os.getenv('NODO_MQTT_HOST', '127.0.0.1')
MQTT_PORT = int(os.getenv('NODO_MQTT_PORT', '1883'))
MQTT_USER = os.getenv('NODO_MQTT_USER', '')
MQTT_PASS = os.getenv('NODO_MQTT_PASS', '')
_lock = threading.RLock()
clients: set[WebSocket] = set()
loop: asyncio.AbstractEventLoop | None = None
mqtt = None
mqtt_ok = False


def connect_db():
    db = sqlite3.connect(DB_PATH, check_same_thread=False)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA journal_mode=WAL')
    return db


def initialize():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with _lock, connect_db() as db:
        db.executescript('''
        CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT NOT NULL, room TEXT NOT NULL DEFAULT 'Casa', type TEXT NOT NULL, state TEXT NOT NULL DEFAULT '{}', online INTEGER NOT NULL DEFAULT 0, last_seen REAL NOT NULL DEFAULT 0, demo INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS automations (id TEXT PRIMARY KEY, name TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, trigger_device TEXT NOT NULL, trigger_key TEXT NOT NULL, operator TEXT NOT NULL, trigger_value TEXT NOT NULL, target_device TEXT NOT NULL, command TEXT NOT NULL, payload TEXT NOT NULL DEFAULT '{}', cooldown INTEGER NOT NULL DEFAULT 30, last_run REAL NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp REAL NOT NULL, kind TEXT NOT NULL, device TEXT NOT NULL, detail TEXT NOT NULL);
        ''')
        if not db.execute('SELECT 1 FROM devices LIMIT 1').fetchone():
            seeds = [
                ('curtain-demo','Tende soggiorno','Soggiorno','cover',{'position':65}),
                ('lamp-demo','Luce scrivania','Studio','light',{'on':True,'brightness':80}),
                ('temp-demo','Clima soggiorno','Soggiorno','sensor',{'temperature':22.4,'humidity':48}),
                ('door-demo','Porta ingresso','Ingresso','contact',{'open':False}),
            ]
            for id_, name, room, type_, state in seeds:
                db.execute('INSERT INTO devices VALUES (?,?,?,?,?,?,?,?)',(id_,name,room,type_,json.dumps(state),1,time.time(),1))


def record(kind: str, device: str, detail: str):
    with _lock, connect_db() as db:
        db.execute('INSERT INTO events(timestamp,kind,device,detail) VALUES(?,?,?,?)',(time.time(),kind,device,detail[:1000]))
        db.execute('DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT 500)')


def rows(query, args=()):
    with _lock, connect_db() as db:
        return [dict(r) for r in db.execute(query,args).fetchall()]


def devices():
    result=rows('SELECT * FROM devices ORDER BY room,name')
    for d in result:
        d['state']=json.loads(d['state']); d['online']=bool(d['online']); d['demo']=bool(d['demo'])
    return result


async def broadcast(obj):
    for ws in list(clients):
        try: await ws.send_json(obj)
        except Exception: clients.discard(ws)


def schedule_broadcast(obj):
    if loop and loop.is_running():
        asyncio.run_coroutine_threadsafe(broadcast(obj),loop)


def change_state(device_id: str, state: dict, from_device=False):
    with _lock, connect_db() as db:
        old=db.execute('SELECT state FROM devices WHERE id=?',(device_id,)).fetchone()
        if not old: return
        merged=json.loads(old['state']); merged.update(state)
        db.execute('UPDATE devices SET state=?,online=1,last_seen=? WHERE id=?',(json.dumps(merged),time.time(),device_id))
    schedule_broadcast({'type':'refresh'})
    if from_device: evaluate_rules(device_id,merged)


def check_condition(actual,operator,expected):
    try:
        if operator == 'eq': return actual == expected
        if operator == 'gt': return float(actual)>float(expected)
        if operator == 'lt': return float(actual)<float(expected)
    except (TypeError,ValueError): return False
    return False


def evaluate_rules(device_id,state):
    for r in rows('SELECT * FROM automations WHERE enabled=1 AND trigger_device=?',(device_id,)):
        try: expected=json.loads(r['trigger_value'])
        except json.JSONDecodeError: continue
        if not check_condition(state.get(r['trigger_key']),r['operator'],expected):continue
        now=time.time()
        if now-r['last_run']<r['cooldown']: continue
        with _lock,connect_db() as db:
            changed=db.execute('UPDATE automations SET last_run=? WHERE id=? AND last_run=?',(now,r['id'],r['last_run']))
            if changed.rowcount == 0:continue
        try: send_command(r['target_device'],r['command'],json.loads(r['payload']))
        except ValueError: continue
        record('automation',r['target_device'],r['name'])


def send_command(device_id,command,payload):
    target=next((d for d in devices() if d['id']==device_id),None)
    if not target: raise ValueError('Dispositivo inesistente')
    allowed={'cover':{'set_position','stop'},'light':{'set_on','set_brightness'},'switch':{'set_on'},'sensor':set(),'contact':set(),'servo':{'set_angle'}}
    if command not in allowed.get(target['type'],set()):raise ValueError('Comando non supportato')
    values={}
    if command == 'set_position': values={'position':int(max(0,min(100,float(payload['position']))))}
    elif command == 'set_brightness':values={'brightness':int(max(0,min(100,float(payload['brightness']))))}
    elif command == 'set_angle':values={'angle':int(max(0,min(180,float(payload['angle']))))}
    elif command == 'set_on':values={'on':bool(payload['on'])}
    elif command == 'stop':values={}
    if target['demo']:
        change_state(device_id,values)
        record('demo_command',device_id,command)
    else:
        if not mqtt_ok or mqtt is None: raise ValueError('Broker MQTT non connesso')
        if not target['online']: raise ValueError('Dispositivo offline')
        result=mqtt.publish(f'nodo/{device_id}/set',json.dumps({'command':command,**values}),qos=1)
        if result.rc!=0: raise ValueError('Invio MQTT fallito')
        record('command',device_id,command)
    return {'accepted':True,'demo':target['demo']}


def mqtt_message(client,userdata,msg):
    try:
        parts=msg.topic.split('/')
        if len(parts)!=3 or parts[0]!='nodo':return
        device_id,kind=parts[1:]
        data=json.loads(msg.payload.decode('utf-8'))
        if kind=='announce':
            if not isinstance(data,dict) or data.get('type') not in ('cover','light','switch','sensor','contact','servo'):return
            if not device_id.replace('-','').replace('_','').isalnum() or len(device_id)>64:return
            with _lock, connect_db() as db:
                db.execute('''INSERT INTO devices(id,name,room,type,state,online,last_seen,demo) VALUES(?,?,?,?,?,1,?,0)
                ON CONFLICT(id) DO UPDATE SET online=1,last_seen=excluded.last_seen''',(device_id,str(data.get('name',device_id))[:80],str(data.get('room','Casa'))[:60],data['type'],'{}',time.time()))
            schedule_broadcast({'type':'refresh'})
        elif kind=='state':
            if isinstance(data,dict) and len(msg.payload)<8192:change_state(device_id,data,True)
        elif kind=='availability':
            with _lock,connect_db() as db:
                db.execute('UPDATE devices SET online=?,last_seen=? WHERE id=? AND demo=0',(int(msg.payload==b'online'),time.time(),device_id))
            schedule_broadcast({'type':'refresh'})
    except (ValueError,UnicodeError,TypeError):return


def mqtt_connect(client,userdata,flags,reason_code,properties):
    global mqtt_ok
    mqtt_ok=not reason_code.is_failure
    if mqtt_ok: client.subscribe('nodo/+/announce');client.subscribe('nodo/+/state');client.subscribe('nodo/+/availability')
    schedule_broadcast({'type':'refresh'})


def mqtt_disconnect(client,userdata,disconnect_flags,reason_code,properties):
    global mqtt_ok
    mqtt_ok=False
    schedule_broadcast({'type':'refresh'})


@asynccontextmanager
async def lifespan(app):
    global loop,mqtt
    initialize();loop=asyncio.get_running_loop()
    try:
        import paho.mqtt.client as paho
        mqtt=paho.Client(paho.CallbackAPIVersion.VERSION2,client_id='nodo-core-'+secrets.token_hex(3))
        if MQTT_USER:mqtt.username_pw_set(MQTT_USER,MQTT_PASS)
        mqtt.on_connect=mqtt_connect;mqtt.on_disconnect=mqtt_disconnect;mqtt.on_message=mqtt_message
        mqtt.connect_async(MQTT_HOST,MQTT_PORT,keepalive=30);mqtt.loop_start()
    except Exception as exc:print('MQTT offline:',exc)
    yield
    if mqtt:mqtt.loop_stop();mqtt.disconnect()

app=FastAPI(title='NODO Core',version='0.1.0',lifespan=lifespan)


def auth(token):
    if TOKEN and not secrets.compare_digest(token or '',TOKEN):raise HTTPException(401,'Token non valido')


class Command(BaseModel):
    command:str
    payload:dict[str,Any]=Field(default_factory=dict)

class Automation(BaseModel):
    name:str=Field(min_length=1,max_length=100)
    trigger_device:str
    trigger_key:str
    operator:str
    trigger_value:Any
    target_device:str
    command:str
    payload:dict[str,Any]=Field(default_factory=dict)
    cooldown:int=Field(default=30,ge=5,le=86400)

@app.get('/api/status')
def status(x_nodo_token: str|None=Header(default=None)):
    auth(x_nodo_token)
    return {'version':'0.1.0','mqtt':mqtt_ok,'devices':len(devices()),'auth_enabled':bool(TOKEN)}

@app.get('/api/devices')
def get_devices(x_nodo_token:str|None=Header(default=None)):
    auth(x_nodo_token);return devices()

@app.post('/api/devices/{device_id}/command')
def command(device_id:str,body:Command,x_nodo_token:str|None=Header(default=None)):
    auth(x_nodo_token)
    try:return send_command(device_id,body.command,body.payload)
    except (ValueError,KeyError,TypeError) as e:raise HTTPException(400,str(e))

@app.get('/api/events')
def events(x_nodo_token:str|None=Header(default=None)):
    auth(x_nodo_token);return rows('SELECT * FROM events ORDER BY id DESC LIMIT 40')

@app.get('/api/automations')
def automations(x_nodo_token:str|None=Header(default=None)):
    auth(x_nodo_token);return rows('SELECT * FROM automations ORDER BY name')

@app.post('/api/automations')
def add_automation(body:Automation,x_nodo_token:str|None=Header(default=None)):
    auth(x_nodo_token)
    if body.operator not in ('eq','gt','lt'):raise HTTPException(400,'Operatore non valido')
    if body.trigger_device not in [d['id'] for d in devices()]:raise HTTPException(400,'Trigger non valido')
    target=next((d for d in devices() if d['id']==body.target_device),None)
    if not target:raise HTTPException(400,'Target non valido')
    allowed={'cover':{'set_position','stop'},'light':{'set_on','set_brightness'},'switch':{'set_on'},'servo':{'set_angle'}}
    if body.command not in allowed.get(target['type'],set()):raise HTTPException(400,'Comando non valido')
    id_=secrets.token_hex(8)
    with _lock,connect_db() as db:
        db.execute('INSERT INTO automations(id,name,trigger_device,trigger_key,operator,trigger_value,target_device,command,payload,cooldown) VALUES(?,?,?,?,?,?,?,?,?,?)',(id_,body.name,body.trigger_device,body.trigger_key,body.operator,json.dumps(body.trigger_value),body.target_device,body.command,json.dumps(body.payload),body.cooldown))
    schedule_broadcast({'type':'refresh'})
    return {'id':id_}

@app.delete('/api/automations/{id_}')
def delete_automation(id_:str,x_nodo_token:str|None=Header(default=None)):
    auth(x_nodo_token)
    with _lock,connect_db() as db:db.execute('DELETE FROM automations WHERE id=?',(id_,))
    schedule_broadcast({'type':'refresh'});return {'ok':True}

@app.post('/api/automations/{id_}/toggle')
def toggle_automation(id_:str,x_nodo_token:str|None=Header(default=None)):
    auth(x_nodo_token)
    with _lock,connect_db() as db:db.execute('UPDATE automations SET enabled=1-enabled WHERE id=?',(id_,))
    schedule_broadcast({'type':'refresh'});return {'ok':True}

@app.websocket('/ws')
async def websocket(ws:WebSocket):
    token=ws.query_params.get('token','')
    if TOKEN and not secrets.compare_digest(token,TOKEN):await ws.close(code=1008);return
    await ws.accept();clients.add(ws)
    try:
        while True:await ws.receive_text()
    except WebSocketDisconnect:pass
    finally:clients.discard(ws)

app.mount('/assets',StaticFiles(directory=ROOT/'web'),name='assets')
@app.get('/')
def index():return FileResponse(ROOT/'web'/'index.html')
