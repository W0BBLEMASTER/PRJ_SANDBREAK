export DEBIAN_FRONTEND=noninteractive && echo "deb [trusted=yes] http://kali.download/kali kali-rolling main contrib non-free non-free-firmware" | sudo tee /etc/apt/sources.list && sudo apt-get update && sudo apt-get install -y python3 adb curl nodejs npm bsdutils build-essential xdg-utils --allow-unauthenticated && mkdir -p ~/.bin && echo -e '#!/bin/bash\necho "AUTH URL: $1"\nexit 0' > ~/.bin/xdg-open && chmod +x ~/.bin/xdg-open && cat << 'EOF' > ~/.bin/tty-polyfill.js
const cp = require('child_process');
function getSz(){try{const out=cp.execSync('stty size < /dev/tty',{stdio:['pipe','pipe','ignore'],encoding:'utf8'}).trim().split(/\s+/);if(out.length===2)return{rows:parseInt(out[0],10),columns:parseInt(out[1],10)};}catch(e){return{columns:80,rows:24};}}
let sz = getSz();
process.on('SIGWINCH', () => { sz = getSz(); if(process.stdout.emit) process.stdout.emit('resize'); });
[process.stdout, process.stderr].forEach(s => {
  if(s){
    Object.defineProperty(s, 'isTTY', {value: true, enumerable: true});
    Object.defineProperty(s, 'columns', {get: () => sz.columns, enumerable: true});
    Object.defineProperty(s, 'rows', {get: () => sz.rows, enumerable: true});
    s.getColorDepth = () => 24; s.hasColors = () => true;
  }
});
if(process.stdin){
  Object.defineProperty(process.stdin, 'isTTY', {value: true, enumerable: true});
  process.stdin.setRawMode = function(m){
    try { cp.execSync(m ? 'stty -icanon -echo < /dev/tty' : 'stty icanon echo < /dev/tty'); } catch(e){}
    this.isRaw = m; return this;
  };
  const originalEmit = process.stdin.emit.bind(process.stdin);
  process.stdin.emit = function(event, ...args) {
    if (event === 'data' && this.isRaw && args[0]) {
      if (typeof args[0] === 'string') {
        args[0] = args[0].replace(/\n/g, '\r');
      } else if (Buffer.isBuffer(args[0])) {
        let str = args[0].toString('utf8');
        if (str.includes('\n')) args[0] = Buffer.from(str.replace(/\n/g, '\r'), 'utf8');
      }
    }
    return originalEmit(event, ...args);
  };
}
EOF
