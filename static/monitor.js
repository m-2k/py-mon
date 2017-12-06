var stop;
var timeout = 10000;
var offline;
var json_url_stat_all = window.location.origin + "/py-mon-stat";
var json_url_stop_all = window.location.origin + "/cmd-stop-all";
var json_url_stop = window.location.origin + "/cmd-stop?node=";
var loaded_last_raw_data = [];

function init() {
    stop = false;
    offline = false;
    timeout = timeout || 10000;
    var bsa = document.getElementById('button-stop-all');
    var requestAnimationFrame = window.requestAnimationFrame || window.mozRequestAnimationFrame || window.webkitRequestAnimationFrame;
    window.requestAnimationFrame = requestAnimationFrame;
    bsa && bsa.addEventListener('click', function(e) {
        var fun_error = function(code,data) { code !== 1 && alert('error') };
        var fun_success = function(json) { console.log(json) };
        json_request(json_url_stop_all, fun_success, fun_error);
    });
    setTimeout(function loop() {
      get_statistics();
      if(stop === false) { setTimeout(loop, timeout); }
    }, 100);
};

var tagsToReplace = { '&': '&amp;', '<': '&lt;', '>': '&gt;' };
function replaceTag(tag) { return tagsToReplace[tag] || tag; };
function safe_tags_replace(str) { return str ? str.replace(/[&<>]/g, replaceTag) : "NULL"; };

function get_statistics() {
    var fun_error = function(code,data) {
        switch(code) {
            case 0: show_offline('Offline'); break;
            case 1: if(data === null) console.log('something is wrong...');
                    else show_offline("Json error: " + (data ? data.error : 'null')); break;
            case 2: show_offline("Unable load resource: " + data); break;
        }
    };
    var fun_success = function(json) {
        loaded_last_raw_data = json;
        requestAnimationFrame(function(timestamp){
            show_online();
            parse_last_statistic();
        });
    };
    json_request(json_url_stat_all, fun_success, fun_error);
};

function json_request(url, fun_success, fun_error) {
    var xhr = new XMLHttpRequest();
    xhr.open('get', url, true);
    xhr.responseType = 'json';
    xhr.addEventListener('error',function(e) { fun_error(0,e); }, false);
    xhr.onload = function() {
        if (xhr.status == 200) {
            var json = (typeof xhr.response == 'string') ? JSON.parse(xhr.response) : xhr.response; // IE 11 Fix
            if(json && json.error === undefined) fun_success(json);
            else { fun_error(1,json); }
        }
        else { fun_error(2,xhr.status); }
    };
    xhr.send();
};

function clear_node_list() {
    var groups = document.querySelectorAll('.group');
    for (var i=0, max=groups.length; i < max; i++) {
        while (groups[i].firstChild) {
            groups[i].removeChild(groups[i].firstChild);
        }
    }
    
};

function insert_before(container_id, html) {
    var div = document.createElement('div');
    div.innerHTML = html;
    var container = document.getElementById(container_id);
    container.appendChild(div.firstChild);
};

function parse_last_statistic() {
    clear_node_list();
    
    for (node of loaded_last_raw_data) {
        var group = node.group ? node.group : 'unknown';
        insert_before(group,render_node(node));
    }
};

function param(classes,warn,body) {
    return '<div class="' + classes + (warn ? ' warn' : '') + '">'+ body + '</div>';
}

function render_node(node) {
    var html = '<div class="name"><span><strong>' + node.desc + '</strong></span></div>';
    var html_part = "";
    var warn_cpu, warn_la, warn_mount, warn_socket, warn_value, warn_latency, warn_python, warn_db, warn_mem;
    
    if(node.status === "OK") {

        if (node.loadavg) {
            var la1 = parseFloat(node.loadavg[0]);
            var la2 = parseFloat(node.loadavg[1]);
            var la3 = parseFloat(node.loadavg[2]);
            var warn_la = la1 > 1.0 || la2 > 0.8 || la3 > 0.8;
            html_part = '<span>' + la1.toFixed(1) + '</span>';
            html_part += '<span>' + la2.toFixed(1) + '</span>';
            html_part += '<span>' + la3.toFixed(1) + '</span>';
            html += param("la",warn_la,'<div>' + html_part + '</div>');
        }
        
        if(node.mem) {
            var mem_virt = parseFloat(node.mem[0]);
            var mem_swap = parseFloat(node.mem[1]);
            warn_mem = mem_virt > 50 || mem_swap > 50;
        
            html_part = '<span>Memory</span>'
            html_part += '<span><span class="minor">virt</span> ' + mem_virt.toFixed(1) + '<span class="minor">%</span></span>';
            html_part += '<span><span class="minor">swap</span> ' + mem_swap.toFixed(1) + '<span class="minor">%</span></span>';
            html += param("mem",warn_mem,html_part);
        }
    
    }
    
    if(node.urls) for (url of node.urls) {
        
        var latency = parseFloat(url.time)*1000;
        
        
        var warn_l = latency > 50.0;
        var warn_c = (url.code !== 200 && url.code !== 401)
        
        warn_latency = warn_latency || warn_l;
        warn_value = warn_value || warn_c;
        
        switch (url.code) {
            case undefined:
                html_part = '<span>Not defined</span>'; break;
            default:
                html_part = '<span>' + url.desc + '</span>'
                html_part += '<span class="code">' + url.code + '</span>'
                html_part += '<span class="time">' + latency.toFixed(2) + '<span class="minor">ms</span></span>'
                //html_part += '<span class="code">' + safe_tags_replace(url.data) + '</span>'
            }
        html += param("app",(warn_l || warn_c),html_part);
    }
    
    if(node.db) for (db of node.db) {
            var warn = db.status !== 'OK';
            warn_db = warn_db || warn;
            if(db.status === 'OK') { html_part = '<span>OK</span><span>'+db.data+'</span>';}
            else { html_part = '<span>N/A</span>'; }
            html += param("db",warn,'<span>' + db.desc + '</span>' + html_part);
        }
    
    if(node.status === "OK") {
        warn_socket = false;
        warn_cpu = parseFloat(node.cpu) > 50;
        html += '<div class="expanded left">';
        html += param("cpu",warn_cpu,'<span>CPU</span><span>' + node.cpu + '<span class="minor">%</span></span>');
        for (port of node.ports) {
            var warn = port.is_used !== true;
            warn_socket = warn_socket || warn;
            if(port.is_used === true) { html_part = '<span>Used</span>';}
            else { html_part = '<span>Unused</span>'; }
            html += param("socket",warn,'<span>' + port.port + '</span>' + html_part);
        }
        html += '</div>';
        
        warn_mount = false;
        html += '<div class="expanded right">';
        if(node.mounts) for (mount of node.mounts) {
            var warn = false;
            if(mount.status === "OK") {
                html_part = '<span>' + mount.perc_formatted + '<span class="minor">%</span></span>';
                if(parseFloat(mount.perc_formatted) > 90.0) { warn = true; }
            } else { html_part = '<span>Unknown</span>'; warn = true; }
            html += param("mount",warn,'<span>' + mount.mount + '</span>' + html_part);
            warn_mount = warn_mount || warn;
        }
        html += '</div>';
    }
    
    html += '<div class="technical"><div class="left">v.'+node.version+'</div>'+
        '<div class="right"><a href="javascript:void();" data-node="'+node.node+'" onclick="action_stop_node(this);">Stop</button></div></div>';
    return '<div class="node ' + (node.status === "OK" ? 'available' : 'unavailable') + '">' +
    '<div class="warn-smart">' +
    param("cpu",warn_cpu,"") +
    param("mem",warn_mem,"") +
    param("la",warn_la,"") +
    param("app",(warn_value || warn_latency),"") +
    param("socket",warn_socket,"") +
    param("mount",warn_mount,"") +
    param("db",warn_db,"") +
    '</div><div class="container">' + html + '</div></div>';
};

function action_stop_all_nodes() {
    json_request(json_url_stop_all, function(json) { console.log(json) }, function(code,data) { alert('error') });
};

function action_stop_node(btn) {
    var url = json_url_stop + btn.dataset.node;
    json_request(url, function(json) { console.log(json) }, function(code,data) { alert('error') });
};

function show_offline(msg) {
    offline = true;
    console.log(msg)
    var b = document.getElementById('viewbox');
    b.innerHTML = '<p>'+msg.toUpperCase()+'</p>';
    b.classList.remove('hidden');
};
function show_online() {
    offline = false;;
    console.log('online');
    var b = document.getElementById('viewbox');
    b.classList.add('hidden');
};
