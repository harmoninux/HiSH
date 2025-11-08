# C/C++

开发者可以使用 HiSH 提供的 Linux 环境中进行 Linux C/C++ 编程，在 Pad 和 PC 上，HiSH能够提供较为完整的使用命令界面编程的体验。

## 准备

在 Alpine Linux 中使用 apk 安装 `gcc musl-dev vim` 三个软件包。

```
apk add gcc musl-dev vim
```

## Hello World

此处以编写 Hello World 为例，使用 `vim hello.c` 命令启动编辑器，编辑代码文件 `hello.c`。

并输入代码：

```
#include <stdio.h>

int main() {
    printf("Hello World!\n");
    return 0;
}
```

<img src="images/07_001.png" width="400"/>

需要注意，`vim`启动后，需要先按下`i`键以进入编辑模式，然后开始编写代码。编写完成后，按下`Esc`退出编辑模式，然后输入`:wq`保存文件并退出。

## 编译运行

`hello.c` 文件编辑好后，使用 `gcc hello.c -o hello` 编译代码，得到编译后的程序文件 `hello`。

输入`./hello`运行编译好的 Hello World 程序，如下：

<img src="images/07_002.png" width="400"/>

