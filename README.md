# 车位记录 HarmonyOS HAP Demo

这是一个 ArkTS Stage 模型的鸿蒙应用示例，用于记录用户停车位置。应用支持手动输入、拍照识别、语音识别，也支持开启系统相机照片监听：用户直接用系统相机拍停车场照片后，应用在后台识别车位号和区域号，并通过通知与桌面卡片展示最新停车信息。

## 功能

- 主界面展示最近一次保存的停车位置，包含车位号、区域号、来源和更新时间。
- 支持手机键盘直接输入车位号。
- 支持选择车位照片，将图片转为 data URL 后通过兼容 Chat Completions 结构的多模态 API 抽取车位号和区域号。
- 支持真实录音输入：录音保存为应用缓存中的 M4A 文件，转 base64 后交给配置的语音/多模态 API 抽取车位号。
- 支持开启系统相机监听：用户授权后用系统相机拍照，应用后台监听新增照片，识别成功后保存停车位置并发送系统通知。
- 支持两阶段图片识别以节省 token：先用极小图判断是否为停车场景，只有命中停车场景时才用较大缩略图识别车位号和区域号。
- 支持 Form Kit 桌面卡片：卡片显示最新停车信息，新停车位置会覆盖旧停车位置。
- 使用 Preferences 本地持久化保存最近一次记录。

## 系统相机监听

系统相机监听入口在主界面的“系统相机监听”开关。开启后应用会请求相册读取、后台运行、通知和网络等权限，并启动用户可见的后台连续任务通知。受 HarmonyOS 系统策略限制，该能力不是无感隐藏监听，必须由用户显式开启，并通过常驻后台通知提示正在监听。

监听流程：

1. 监听媒体库新增照片。
2. 过滤监听开启之前的图片和已处理过的图片。
3. 请求 `192px` 缩略图，调用大模型判断是否为停车场、地下车库、停车楼或车位场景。
4. 如果是停车场景，再请求 `512px` 缩略图，调用大模型识别车位号和立柱/区域号。
5. 只有识别结果包含合理停车位置且置信度达标时，才保存记录并发送通知。

相关代码：

- `entry/src/main/ets/services/CameraPhotoMonitor.ets`
- `entry/src/main/ets/services/ImagePreprocessor.ets`
- `entry/src/main/ets/services/ParkingNotificationService.ets`

## 桌面卡片

项目使用 Form Kit 提供一个 `2*2` 桌面卡片，展示最新停车位置。添加卡片后，应用每次保存新的停车记录都会调用 `formProvider.updateForm` 刷新所有已登记的卡片；清空停车记录时，卡片也会回到“暂无停车位置”状态。

相关代码：

- `entry/src/main/ets/entryformability/EntryFormAbility.ets`
- `entry/src/main/ets/services/ParkingFormService.ets`
- `entry/src/main/ets/widget/pages/ParkingCard.ets`
- `entry/src/main/resources/base/profile/form_config.json`

## AI 接入位置

在 `entry/src/main/ets/services/RecognizerConfig.ets` 中配置：

```ts
export const DEFAULT_AI_CONFIG = {
  provider: 'custom',
  endpoint: 'https://你的服务地址/v1/chat/completions',
  apiKey: '你的 API Key',
  model: 'qwen-vl-plus'
};
```

`AiParkingRecognizer.ets` 采用 `Authorization: Bearer <apiKey>` 和 Chat Completions 风格的请求体。豆包、Qwen 或自建网关只要适配该结构即可直接使用；如果服务商字段不同，可主要修改这个文件。

图片输入会被转成 `data:image/jpeg;base64,...`。系统相机监听使用两种压缩配置：

- 场景判断：长边 `192px`，JPEG 质量 `55`，只判断是否为停车场景。
- 停车位置识别：长边 `512px`，JPEG 质量 `72`，识别车位号和区域号。

语音输入由 `VoiceRecorder.ets` 录制为 M4A，再通过 `recognizeFromAudioFile` / `recognizeFromAudioBase64` 发送给接口。

## 使用

用 DevEco Studio 打开本目录，配置签名后运行 `entry` 模块即可生成并安装 HAP。

也可以使用当前 Hvigor 命令构建：

```bash
NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleApp --no-daemon
```

当前工程已用上述命令验证通过。构建时可能出现部分 SDK 兼容性或异常处理 warning，例如媒体库 `photoChange`、`createScaledPixelMap` 和若干 API 的 throws 提示；这些 warning 不影响当前 HAP 打包。
