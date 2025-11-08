# 包管理器

Alpine 使用自有的 apk（Alpine Package Keeper）作为包管理器，它提供了安装、更新、删除和查询软件包的功能。

apk 工具设计简洁高效，适合在轻量化的环境中使用，能够自动解决依赖关系并管理本地缓存。

在 Linux Shell 中，运行`apk`即可看到包管理器输出的帮助文档。

## 安装软件包

使用 `apk add` 命令可以安装软件包，并自动解决依赖关系。

例如，安装 `openssh` 和 `vim` 可以运行 `apk add openssh
vim`。



如果需要安装指定版本的软件包，可以使用 `apk add package=version` 的格式，例如 `apk add asterisk=1.6.0.21-r0`。

此外，`--no-cache`
选项可以避免生成缓存文件，适合在模拟器中使用以减少对镜像空间的占用。

## 搜索软件包

通过 `apk search` 命令可以搜索可用的软件包。

例如，`apk search -v` 会列出所有可用软件包及其描述，而 `apk search -v 'nginx*'` 可以搜索名称匹配 `nginx*` 的软件包。`-d`
选项允许通过描述信息搜索，例如 `apk search -v -d 'web server'`

## 查看已安装的软件包

使用 `apk info` 可以查看已安装的软件包列表，`apk info -v` 会显示详细信息，包括版本和依赖关系。

要查看某个文件属于哪个软件包，可以使用 `apk info --who-owns /path/to/file`，例如 `apk info --who-owns /sbin/apk`。

## 删除软件包

`apk del` 命令用于卸载软件包及其依赖项。例如，删除 `openssh` 可以运行 `apk del openssh`。

删除操作会同时清理不再需要的依赖包，但不会自动清理缓存文件，需要手动运行 `apk cache clean` 来清理缓存。

## 更改软件源

Alpine 的软件源配置文件位于 `/etc/apk/repositories`，默认使用官方镜像源。

可以编辑此文件，替换为国内镜像源以提高下载速度，例如阿里云或中科大源。更改后需运行 `apk update` 更新本地索引。

例如，添加阿里云源可以执行
```
echo "https://mirrors.aliyun.com/alpine/v3.22/main" > /etc/apk/repositories
echo "https://mirrors.aliyun.com/alpine/v3.22/community" >> /etc/apk/repositories
```
