// Matrix Rain Implementation for HiSH
class Trail {
    constructor(column, fontSize, canvasHeight, chars) {
        this.column = column;
        this.fontSize = fontSize;
        this.canvasHeight = canvasHeight;
        this.chars = chars;
        this.rows = Math.ceil(canvasHeight / fontSize) + 2;
        this.body = [];
        this.isBinary = false;
        this.options = {
            size: Math.floor(Math.random() * 20) + 10, // 轨迹长度 r(10, 30)
            offset: Math.floor(Math.random() * this.rows) // 初始偏移
        };
        this.build();
    }

    build() {
        this.body = [];
        for (let i = 0; i < this.rows; i++) {
            this.body.push({
                char: this.getRandomChar(),
                mutate: Math.random() < 0.5
            });
        }
    }

    getRandomChar() {
        return this.chars.charAt(Math.floor(Math.random() * this.chars.length));
    }

    update() {
        this.options.offset = (this.options.offset + 1) % (this.rows + this.options.size);
        const mutationRate = this.isBinary ? 0.3 : 0.02;
        this.body.forEach(c => {
            if (c.mutate && Math.random() < mutationRate) {
                c.char = this.getRandomChar();
            }
        });
    }

    draw(ctx) {
        const { offset, size } = this.options;
        const x = this.column * this.fontSize;
        for (let i = 0; i < size; i++) {
            const index = offset + i - size + 1;
            if (index >= 0 && index < this.rows) {
                const c = this.body[index];
                const charY = index * this.fontSize;
                const last = (i === size - 1);
                if (last) {
                    ctx.fillStyle = 'hsl(136, 100%, 85%)';
                    ctx.shadowBlur = 12;
                    ctx.shadowColor = '#fff';
                    c.char = this.getRandomChar();
                } else {
                    const brightness = (85 / size) * (i + 1);
                    ctx.fillStyle = `hsl(136, 100%, ${brightness}%)`;
                    ctx.shadowBlur = 0;
                    ctx.shadowColor = 'transparent';
                }
                ctx.fillText(c.char, x, charY);
            }
        }
    }
}

class MatrixRain {
    constructor(canvasId) {
        this.canvas = document.getElementById(canvasId);
        this.ctx = this.canvas.getContext('2d');
        this.trails = [];
        this.fontSize = 16;
        this.isBinary = false;
        this.isScreensaver = false;
        this.chars = this.getSampleCharSet();
        this.animationId = null;
        this.resize();
        window.addEventListener('resize', () => this.resize());
    }

    getSampleCharSet() {
        let chars = '';
        let prioritized = '';
        let junk = '';
        for (let i = 0x3041; i <= 0x30ff; i++) chars += String.fromCharCode(i);
        for (let i = 0x0041; i <= 0x005a; i++) prioritized += String.fromCharCode(i);
        for (let i = 0x0061; i <= 0x007a; i++) prioritized += String.fromCharCode(i);
        prioritized += '0123456789!@#$%^&*()_+-=[]{}|;:\'",.<>?/\\';
        junk += '█▓▒░√×÷±≠≈∞∑∏π∫∆∇√∝∞∟∠∡∢∣∤∥∦∧∨∩∪∫∬∭∮∯∰∱∲∳';
        for (let i = 0x2500; i <= 0x257f; i++) junk += String.fromCharCode(i);
        for (let i = 0x2000; i <= 0x206f; i++) chars += String.fromCharCode(i);
        return chars + prioritized.repeat(6) + junk.repeat(2);
    }

    setCharSet(type) {
        this.isBinary = (type === 'binary');
        this.chars = this.isBinary ? '01' : this.getSampleCharSet();
        this.trails.forEach(t => {
            t.chars = this.chars;
            t.isBinary = this.isBinary;
        });
    }

    resize() {
        this.canvas.width = window.innerWidth;
        this.canvas.height = window.innerHeight;
        const columns = Math.floor(this.canvas.width / this.fontSize);
        this.trails = [];
        for (let i = 0; i < columns; i++) {
            const trail = new Trail(i, this.fontSize, this.canvas.height, this.chars);
            trail.isBinary = this.isBinary;
            this.trails.push(trail);
        }
    }

    draw() {
        const now = Date.now();
        const delay = 50;
        if (!this.lastFrameTime || now - this.lastFrameTime >= delay) {
            if (this.isScreensaver) {
                this.ctx.fillStyle = '#000';
                this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
            } else {
                this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
            }
            this.ctx.font = `bold ${this.fontSize}px monospace`;
            this.ctx.textAlign = 'center';
            this.ctx.shadowBlur = 0;
            this.ctx.shadowColor = 'transparent';
            this.trails.forEach(trail => {
                trail.update();
                trail.draw(this.ctx);
            });
            this.lastFrameTime = now;
        }
        this.animationId = requestAnimationFrame(() => this.draw());
    }

    start() {
        if (!this.animationId) {
            this.canvas.style.display = 'block';
            this.draw();
        }
    }

    stop() {
        if (this.animationId) {
            cancelAnimationFrame(this.animationId);
            this.animationId = null;
            this.canvas.style.display = 'none';
        }
    }
}
