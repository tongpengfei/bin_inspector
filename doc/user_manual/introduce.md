## 前言

在工作中需要查看h264视频数据格式，但是mac下找不到一款好用的，免费的工具，很是不方便。  
于是便有了BinInspector，以下简称BI吧。  

![h264截图](doc/screenshots/mac_h264.png)  


虽然起初是为了查看h264数据，但考虑到除了h264,还mp4,mp3,flv,aac等一系列数据可能需要  
查看，所以为BI留了足够的扩展性，一番思考后，决定使用Qt+lua开发BI。  

工作中也经常需要分析抓包文件，一般都是用wireshark分析，但难免有一些个人需求，比如抓
包太大，想提取出某一路流的抓包数据，或者从抓包文件里提取h264数据等等，于是支持了pcap,   
pcapng格式，可以定制自己的需求。  

![分析抓包文件截图](doc/screenshots/mac_pcap.png)
![从抓包文件里提取h264数据](doc/screenshots/mac_pcap_rtp_extract_h264.png)

这样就可以用BI从抓包文件里提取h264数据，再用BI分析h264数据，只用一个工具就可以了。  

后来在打包windows版本时候，又经常遇到找不到dll的问题，于是把PE格式也支持了，方便查看
dll依赖关系。  

![PE截图](doc/screenshots/mac_exe.png)
![DLL依赖截图](doc/screenshots/mac_exe_depend_dll.png)  

> * Qt负责 ui，跨平台  
> * c++导出lua接口  
> * lua负责解析具体数据格式  

scripts下的脚本称为公共脚本，解析器脚本放在scripts/codec下，BI会自动加载该目录下的  
所有脚本，每一个lua脚本就是一个文件格式解析器，如  
```c
scripts/codec/codec_h264.lua  负责解析h264数据    
scripts/codec/codec_mp4.lua   负责解析mp4数据  
```

BI根据文件名后缀区分使用哪个解析器解析数据，如果是未识别的格式，会使用默认解析器  
codec_default.lua来解析数据，这时候BI其实就是一个二进制数据查看器。  

可以自已扩展解析器，可称之为私有解析器，建议自己扩展的解析脚本放在  
```c
mac: ~/Library/Application\ Support/BinInspector/scripts/codec/         
win: $BI安装路径/.bin_inspector/scripts/codec/
```
目录下，BI会优先加载私有解析器，再加载公共解析器，如果某个文件后缀已经被加载，则  
不会重复加载，所以会优先使用私有解析器。  

公共脚本后面会支持自动更新。  

目前BI支持的数据格式有十几种，还在持续增加中， 


欢迎各位开发上传解析器。 