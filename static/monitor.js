var stop = false;
var timeout = 5000;
var last_values = {};
var json_url = "http://localhost:8001/statistics";
var format_columns = 7;

function init() {
    setTimeout(function loop() {
      get_statistics();
      if(stop === false) { setTimeout(loop, timeout); }
    }, 100);
};

function clear_node_list() {
    var e = document.getElementById("node-list");
    while (e.firstChild) {
      e.removeChild(e.firstChild);
    }
};

var tagsToReplace = { '&': '&amp;', '<': '&lt;', '>': '&gt;' };
function replaceTag(tag) { return tagsToReplace[tag] || tag; };
function safe_tags_replace(str) { return str.replace(/[&<>]/g, replaceTag); };

function get_statistics() {
    var xhr = new XMLHttpRequest();
    xhr.open('get', json_url, true);
    xhr.responseType = 'json';
    xhr.onload = function() {
        var status = xhr.status;
        if (status == 200) {
            // debugger;
            var json = (typeof xhr.response == 'string') ? JSON.parse(xhr.response) : xhr.response; // IE 11 Fix
            if(json.error === undefined) {
                parse_statistic(json);
            }
            else { console.log("json error: " + json.error); }
        }
        else {
            console.log("Unable load resource: " + json_url);
        }
    };
    xhr.send();
};

function parse_statistic(json) {
    // debugger;
    
    clear_node_list();
    
    for (node of json) {
        console.log(node);
        insert_before('node-list',render_node(node));
    }
    for (node of json) {
        actions(node);
    }
}

function create_id(node,param_id) {
    return "id-" + node.node + "-" + param_id;
};

function render_node(node) {
    // if(node.status != "OK") {
    //     return '<div class="node"><div class="node-name"><span>' +
    //         node.node + ": " + node.status +
    //         '</span></div></div>'; };
    var parameters = '';
    var void_p_count = format_columns - 1;
    
    switch (node.code) {
        case undefined:
            parameters += render_parameter(node,"response","","Not Defined","");
            break;
        case 200:
            parameters += render_parameter(node,"response",(node.time * 1000).toFixed(2),node.code,safe_tags_replace(node.data)+"…");
            break;
        default:
            parameters += render_parameter(node,"response",(node.time * 1000).toFixed(2),node.code,node.data);
            break;
        }
    if(node.status === "OK") {
        parameters += render_parameter(node,"cpu",node.cpu,"CPU","Ut, 5s");
    
        parameters += render_parameter(node,"la-1",node.loadavg[0],"1 min","LA");
        parameters += render_parameter(node,"la-2",node.loadavg[1],"5 min","LA");
        parameters += render_parameter(node,"la-3",node.loadavg[2],"15 min","LA");
        
        void_p_count -= 4;
        
        for (mount of node.mounts) {
            void_p_count--;
            if(mount.status === "OK") {
                parameters += render_parameter(node,mount.mount,mount.perc_formatted + "%",
                    mount.mount,(mount.mnt_size/1073741824.0).toFixed(2) + " GB");
            } else {
                parameters += render_parameter(node,mount.mount,"N/A",mount.mount,"Unknown");
            }
        }
        for (port of node.ports) {
            void_p_count--;
            port_id="port-"+port.port;
            if(port.is_used === true) {
                parameters += render_parameter(node,port_id,port.port,"Used","Socket");
            } else {
                parameters += render_parameter(node,port_id,port.port,"Unused","Socket");
            }
        }
    }
    void_parameters = "";
    for(; void_p_count > 0; void_p_count--) {
        void_parameters += '<div class="void-parameter"></div>';
    }
    return '<div class="node">' + render_node_title(node) + parameters + void_parameters +'</div>';
};

function render_node_title(node) {
    return '<div class="node-title"><span>' + node.node + '</span></div>';
};

function render_parameter(node,param_id,value,volume,free) {
    var id = create_id(node,param_id);
    var s = 60;
    var c = s/2;
    var r = 30;
    var text_x = c;
    var text_y = c + 6;
    // var max = 189;
    return '<div class="parameter"><div><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1"' +
        ' viewBox="0 0 ' + s + ' ' + s + '" preserveAspectRatio="none" style="width:' + s + '; height:' + s + '; top:0; left:0;">' +
        '<circle class="background" cx="' + c + '" cy="' + c + '" r="' + r + '" />' +
        '<circle id="svg-' + id + '-circle" class="progress" cx="' + c + '" cy="' + c + '" r="' + r + '" stroke-dasharray="0 400" transform="rotate(-90,' + c + ',' + c + ')" />' +
        '<text id="svg-' + id + '-text-value" class="text-svg" text-anchor="middle" x="' + text_x + '" y="' + text_y + '">' + value + '</text></svg></div><div>' +
        '<span id="svg-' + id + '-text-volume" class="text-primary">' + volume + '</span>' +
        '<span id="svg-' + id + '-text-free" class="text-secondary">' + free + '</span></div></div>';
};

function insert_before(container_id, html) {
    var div = document.createElement('div');
    div.innerHTML = html;
    var container = document.getElementById(container_id);
    container.appendChild(div.firstChild);
};

function actions(node) {
    if(node.status === "OK"){
        switch (node.code) {
            case undefined: a(create_id(node,"response"),0); break;
            case 200: a(create_id(node,"response"),node.time*500); break;
            default: a(create_id(node,"response"),100); break;
            }
        a(create_id(node,"cpu"),parseFloat(node.cpu));
        
        a(create_id(node,"la-1"),node.loadavg[0]);
        a(create_id(node,"la-2"),node.loadavg[1]);
        a(create_id(node,"la-3"),node.loadavg[2]);
        for (mount of node.mounts) {
            if(mount.status === "OK") { a(create_id(node,mount.mount),mount.percent); }
            else { a(create_id(node,mount.mount),100.0); }
        }
        for (port of node.ports) {
            //debugger;
            port_id=create_id(node,"port-"+port.port);
            if(port.is_used === true) { a(port_id,0.0); }
            else { a(port_id,100.0); }
        }
    }
};

function a(id, percent) {
    percent = percent < 0 ? 0 : percent > 100 ? 100 : percent;
    //percent = Math.random() * 99
    // math trick 2*pi*57 = 358, must be less than 360 degree 
    var circle = document.getElementById("svg-" + id + "-circle");
    // var myTimer = document.getElementById('myTimer');
    // debugger
    var time_interval = 10;
    var angle = 0;
    var angle_increment = 1;
    if (last_values[id] !== undefined) {
        angle = last_values[id].angle;
        angle_increment = last_values[id].percent > percent ? -angle_increment : angle_increment;
    }
    //console.log(percent,circle);
    var max = 189;
    var value = percent / 100.0 * max; // in grad
    
    if(circle) {
        var timer = window.setInterval(function () {
            circle.setAttribute("stroke-dasharray", angle + ", 400");
            
            var angle_in_percent = angle * 100.0 / max;
            var R = Math.round(angle_in_percent / 0.397).toString(16)
            var G = Math.round(255 - (angle_in_percent / 0.545)).toString(16)
            var B = Math.round(100 - (angle_in_percent / 2.200)).toString(16)
            circle.setAttribute("stroke", "#" +
                ((R.length < 2) ? "0" + R : R) +
                ((G.length < 2) ? "0" + G : G) +
                ((B.length < 2) ? "0" + B : B));
            // myTimer.innerHTML = parseInt(angle/360*100) + '%';

            if ((angle >= value && angle_increment > 0) || ( angle <= value && angle_increment < 0 )) {
                var lv = {};
                lv.angle = angle;
                lv.percent = percent;
                last_values[id] = lv;
                // debugger;
                window.clearInterval(timer);
            }
            angle += angle_increment;
            if((angle > value && angle_increment > 0) || ( angle < value && angle_increment < 0 )) {
                angle=value;
            }
        }.bind(this), time_interval);
    }
};

// 'http://suo4.cgs.sbrf.ru:8000/get-state?volume=/tmp'
function getJSON(url) {
    if (url == undefined) { console.log("url parameter undefined"); return }
    // return new Promise(function(resolve, reject) {
        var xhr = new XMLHttpRequest();
        xhr.open('get', url, true);
        xhr.responseType = 'json';
        xhr.onload = function() {
            var status = xhr.status;
            if (status == 200) {
                var json = xhr.response;
                //debugger;
                alert(xhr.response);
            }
            else { alert(status); }
        };
        xhr.send();
    // });
};

// function test() {
    // getJSON().then(function(data){ alert(data.result); }, function(status) { alert("ERR" + status); } )
// }

