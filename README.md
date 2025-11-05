# SwiftScaffolding

[Scaffolding 协议](https://github.com/Scaffolding-MC/Scaffolding-MC) 的 Swift 实现。<br>

> [!WARNING]
> 该库仍处于开发阶段，API 可能会发生破坏性更改。
> 

## 用法

### 房间码

生成房间码：
```swift
RoomCode.generate()
```
验证房间码是否符合规范：
```swift
RoomCode.isValid(code: 房间码)
```

### EasyTier

创建 `EasyTier` 实例：
```swift
let easyTier: EasyTier = EasyTier(
    coreURL: URL(filePath: "/usr/bin/easytier-core"), // easytier-core 的路径
    cliURL: URL(filePath: "/usr/bin/easytier-cli"), // easytier-cli 的路径
    logURL: URL(filePath: "/tmp/easytier.log") // easytier-core 日志文件，为 nil 时不保留日志
)
```

### 联机

创建联机客户端并加入目标房间：
```swift
// 1. 创建联机客户端
let client: ScaffoldingClient = ScaffoldingClient(
    easyTier: easyTier, // 使用的 EasyTier
    playerName: "YiZhiMCQiu", // 玩家名
    vendor: "xxx launcher 1.0.0, EasyTier v2.4.5", // 联机客户端信息
    roomCode: "U/ZZZZ-ZZZZ-ZZZZ-ZZZZ" // 房间码
)
Task {
    // 2. 连接到目标房间
    try await client.connect()
    // client.room.serverPort 为 Minecraft 局域网服务器的本地端口
    print("请打开 Minecraft，然后加入：127.0.0.1:\(client.room.serverPort)")
    // 3. 发送心跳包
    while true {
        try await client.heartbeat()
        // heartbeat 被调用后会更新 client.room.members
        print(client.room.members)
        try await Task.sleep(for: .seconds(5))
    }
}
```
创建联机中心：
```swift
// 1. 创建联机中心
let server: ScaffoldingServer = ScaffoldingServer(
    easyTier: easyTier, // 使用的 EasyTier
    roomCode: RoomCode.generate(), // 房间码，需要符合 Scaffolding 规范，否则会在 createRoom() 中抛出错误
    playerName: "MinecraftVenti", // 房主玩家名
    vendor: "xxx launcher 1.0.0, EasyTier v2.4.5", // *联机客户端*信息
    serverPort: 12345 // Minecraft 局域网服务器端口
)
Task {
    do {
        // 2. 开启联机中心 TCP 服务器
        try await server.startListener()
        // 3. 创建 EasyTier 网络
        try server.createRoom()
        print("房间创建成功，房间码：\(server.roomCode)")
    } catch {
        print("房间创建失败：\(error)")
    }
}
```
开启日志输出并设置日志文件：
```swift
try Logger.enableLogging(url: .homeDirectory.appending(path: "swift-scaffolding.log"))
// 注意：日志不会写入到标准输出流
```