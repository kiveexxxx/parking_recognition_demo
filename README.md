# 车位记录 HarmonyOS HAP Demo

这是一个 ArkTS Stage 模型的鸿蒙应用示例，用于记录用户停车车位号。

## 功能

- 主界面展示最近一次保存的车位号。
- 支持手机键盘直接输入车位号。
- 支持选择车位照片，将图片转为 data URL 后通过兼容 Chat Completions 结构的多模态 API 抽取车位号。
- 支持开启系统相机监听：用户授权后用系统相机拍照，应用后台监听新增照片、压缩缩小后识别停车位置，并发送通知。
- 支持真实录音输入：录音保存为应用缓存中的 M4A 文件，转 base64 后交给配置的语音/多模态 API 抽取车位号。
- 使用 Preferences 本地持久化保存最近一次记录。

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

`AiParkingRecognizer.ets` 采用 `Authorization: Bearer <apiKey>` 和 Chat Completions 风格的请求体。豆包、Qwen 或自建网关只要适配该结构即可直接使用；如果服务商字段不同，可只修改这个文件。图片输入会被转成 `data:image/jpeg;base64,...`；系统相机监听会先通过 `ImagePreprocessor.ets` 将图片长边控制到 1280px，必要时降到 960px，以减少 token 消耗；语音输入由 `VoiceRecorder.ets` 录制为 M4A，再通过 `recognizeFromAudioFile` / `recognizeFromAudioBase64` 发送给接口。

## 使用

用 DevEco Studio 打开本目录，配置签名后运行 `entry` 模块即可生成并安装 HAP。
