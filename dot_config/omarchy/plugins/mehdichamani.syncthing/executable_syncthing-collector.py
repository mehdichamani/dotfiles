#!/usr/bin/env python3
import os
import sys
import json
import urllib.request
import urllib.parse
import urllib.error
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor

def get_syncthing_config():
    paths = [
        os.path.expanduser("~/.local/state/syncthing/config.xml"),
        os.path.expanduser("~/.config/syncthing/config.xml"),
    ]
    for p in paths:
        if os.path.isfile(p):
            try:
                tree = ET.parse(p)
                root = tree.getroot()
                apikey_el = root.find("gui/apikey")
                address_el = root.find("gui/address")
                apikey = apikey_el.text.strip() if apikey_el is not None and apikey_el.text else ""
                addr = address_el.text.strip() if address_el is not None and address_el.text else "127.0.0.1:8384"
                if apikey:
                    return {"apikey": apikey, "address": addr, "config_path": p}
            except Exception:
                pass
    return None

def fetch_json(url, headers, timeout=2.5):
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None
    return None

def fetch_folder_status(base_url, headers, folder):
    fid = folder.get("id")
    url = f"{base_url}/rest/db/status?folder={urllib.parse.quote(fid)}"
    st = fetch_json(url, headers, timeout=2.0) or {}
    
    state = (st.get("state") or "unknown").lower()
    errors = st.get("errors", 0) + st.get("pullErrors", 0)
    need_bytes = st.get("needBytes", 0)
    global_bytes = st.get("globalBytes", 0)
    in_sync_bytes = st.get("inSyncBytes", 0)
    need_files = st.get("needFiles", 0)
    need_deletes = st.get("needDeletes", 0)
    
    sync_pct = 100
    if global_bytes > 0:
        sync_pct = round(max(0, min(100, (in_sync_bytes / float(global_bytes)) * 100)), 1)
    elif need_bytes > 0:
        sync_pct = 0

    return {
        "id": fid,
        "label": folder.get("label") or fid,
        "path": folder.get("path") or "",
        "paused": folder.get("paused", False),
        "state": state,
        "syncPercentage": sync_pct,
        "errors": errors,
        "needFiles": need_files,
        "needDeletes": need_deletes,
        "needBytes": need_bytes,
        "globalBytes": global_bytes,
        "globalFiles": st.get("globalFiles", 0),
        "inSyncBytes": in_sync_bytes,
        "inSyncFiles": st.get("inSyncFiles", 0),
        "watchError": st.get("watchError", "")
    }

def fetch_device_completion(base_url, headers, dev_id):
    url = f"{base_url}/rest/db/completion?device={urllib.parse.quote(dev_id)}"
    comp = fetch_json(url, headers, timeout=2.0) or {}
    return {
        "completion": comp.get("completion", 100),
        "needBytes": comp.get("needBytes", 0),
        "needItems": comp.get("needItems", 0),
        "needDeletes": comp.get("needDeletes", 0),
    }

def main():
    cfg = get_syncthing_config()
    if not cfg:
        print(json.dumps({
            "isAvailable": False,
            "overallStatus": "attention",
            "error": "Syncthing configuration not found",
            "folders": [],
            "devices": [],
            "totalFolders": 0,
            "syncingFolders": 0,
            "idleFolders": 0,
            "errorFolders": 0,
            "totalDevices": 0,
            "connectedDevices": 0,
            "guiUrl": "http://127.0.0.1:8384"
        }))
        return

    base_url = f"http://{cfg['address']}"
    headers = {"X-API-Key": cfg["apikey"]}

    sys_status = fetch_json(f"{base_url}/rest/system/status", headers)
    if not sys_status:
        print(json.dumps({
            "isAvailable": False,
            "overallStatus": "attention",
            "error": "Syncthing service is stopped or unreachable",
            "folders": [],
            "devices": [],
            "totalFolders": 0,
            "syncingFolders": 0,
            "idleFolders": 0,
            "errorFolders": 0,
            "totalDevices": 0,
            "connectedDevices": 0,
            "guiUrl": base_url
        }))
        return

    my_id = sys_status.get("myID", "")
    uptime_sec = sys_status.get("uptime", 0)

    with ThreadPoolExecutor(max_workers=4) as ex:
        f_conns = ex.submit(fetch_json, f"{base_url}/rest/system/connections", headers)
        f_devices = ex.submit(fetch_json, f"{base_url}/rest/config/devices", headers)
        f_folders = ex.submit(fetch_json, f"{base_url}/rest/config/folders", headers)

        conns_data = f_conns.result() or {}
        raw_devices = f_devices.result() or []
        raw_folders = f_folders.result() or []

    connections = conns_data.get("connections", {})
    total_in_bytes = conns_data.get("total", {}).get("inBytesTotal", 0)
    total_out_bytes = conns_data.get("total", {}).get("outBytesTotal", 0)

    folders = []
    with ThreadPoolExecutor(max_workers=6) as ex:
        futures = [ex.submit(fetch_folder_status, base_url, headers, f) for f in raw_folders]
        for fut in futures:
            res = fut.result()
            if res:
                folders.append(res)

    folders.sort(key=lambda x: (x["paused"], x["state"] == "idle", x["label"].lower()))

    # Fetch completion for remote devices
    remote_raw = [d for d in raw_devices if d.get("deviceID", "") != my_id]
    device_completions = {}
    with ThreadPoolExecutor(max_workers=4) as ex:
        futures = {d.get("deviceID", ""): ex.submit(fetch_device_completion, base_url, headers, d.get("deviceID", "")) for d in remote_raw}
        for did, fut in futures.items():
            device_completions[did] = fut.result()

    devices = []
    connected_count = 0
    all_devices_up_to_date = True
    any_device_syncing = False
    any_device_attention = False

    for d in remote_raw:
        dev_id = d.get("deviceID", "")
        c_info = connections.get(dev_id, {})
        is_connected = bool(c_info.get("connected", False))
        is_paused = bool(d.get("paused", False))
        if is_connected:
            connected_count += 1

        comp_info = device_completions.get(dev_id, {"completion": 100, "needBytes": 0, "needItems": 0})
        completion = comp_info.get("completion", 100)
        need_bytes = comp_info.get("needBytes", 0)

        # Status text and state
        if is_paused:
            status_text = "Paused"
            any_device_attention = True
            all_devices_up_to_date = False
        elif not is_connected:
            status_text = "Disconnected"
            any_device_attention = True
            all_devices_up_to_date = False
        elif completion < 100 or need_bytes > 0:
            status_text = f"Syncing ({completion:.0f}%)"
            any_device_syncing = True
            all_devices_up_to_date = False
        else:
            status_text = "Up to Date"

        devices.append({
            "id": dev_id,
            "shortId": dev_id[:7] if dev_id else "",
            "name": d.get("name") or dev_id[:7],
            "connected": is_connected,
            "paused": is_paused,
            "completion": completion,
            "needBytes": need_bytes,
            "statusText": status_text,
            "address": c_info.get("address", ""),
            "clientVersion": c_info.get("clientVersion", ""),
            "inBytesTotal": c_info.get("inBytesTotal", 0),
            "outBytesTotal": c_info.get("outBytesTotal", 0)
        })

    devices.sort(key=lambda x: (not x["connected"], x["name"].lower()))

    syncing_folders = sum(1 for f in folders if f["state"] in ("syncing", "sync-preparing", "scanning"))
    error_folders = sum(1 for f in folders if f["errors"] > 0 or f["state"] == "error")
    idle_folders = sum(1 for f in folders if f["state"] == "idle" and not f["paused"])

    # Calculate overallStatus: 'attention' | 'syncing' | 'ok'
    if error_folders > 0 or any_device_attention or (len(devices) > 0 and connected_count == 0):
        overall_status = "attention"
    elif syncing_folders > 0 or any_device_syncing:
        overall_status = "syncing"
    elif all_devices_up_to_date and len(devices) > 0:
        overall_status = "ok"
    else:
        overall_status = "ok"

    output = {
        "isAvailable": True,
        "overallStatus": overall_status,
        "myID": my_id,
        "uptime": uptime_sec,
        "guiUrl": base_url,
        "totalInBytes": total_in_bytes,
        "totalOutBytes": total_out_bytes,
        "folders": folders,
        "devices": devices,
        "totalFolders": len(folders),
        "syncingFolders": syncing_folders,
        "idleFolders": idle_folders,
        "errorFolders": error_folders,
        "totalDevices": len(devices),
        "connectedDevices": connected_count
    }

    print(json.dumps(output))

if __name__ == "__main__":
    main()

