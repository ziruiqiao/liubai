# 第三方参考与声明

参考项目：[wood3n/biu](https://github.com/wood3n/biu)。

WBI 请求签名的密钥重排和参数处理，参考了该项目的 [`electron/ipc/api/wbi.ts`](https://github.com/wood3n/biu/blob/master/electron/ipc/api/wbi.ts)，并用 Swift 重新实现。音频解析接口结构参考了其 DASH 请求及相关类型。

扫码登录、收藏夹读取和合集 / 系列列表的接口结构也参考了该项目的 `src/service/`。原生扫码界面、钥匙串保存、只读请求限制、分页导入和本地合集逻辑均用 Swift 编写。

Required Notice: Copyright (c) 2022–2025 wood3n

该参考实现采用 **PolyForm Noncommercial License 1.0.0**，完整许可保存在 [biu-LICENSE.txt](biu-LICENSE.txt)，随应用资源一同分发。当前原型用于个人非商业使用；若计划商业发行，需要重新核对参考实现的授权范围。

留白为非官方客户端，与哔哩哔哩无官方关联或背书。
