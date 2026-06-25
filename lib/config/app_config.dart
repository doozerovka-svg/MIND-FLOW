enum InputMode {
  tap,
  hold,
}

enum LlmProvider {
  openai,
  deepseek,
}

class AppConfig {
  static String openAiApiKey = '';
  static String deepSeekApiKey = '';
  
  static InputMode inputMode = InputMode.tap;
  static LlmProvider llmProvider = LlmProvider.openai;

  // Endpoint URLs (can be overridden if needed for local mock servers or proxies)
  static String whisperUrl = 'https://api.openai.com/v1/audio/transcriptions';
  static String openAiGptUrl = 'https://api.openai.com/v1/chat/completions';
  static String deepSeekUrl = 'https://api.deepseek.com/chat/completions';

  // LLM Models
  static String gptModel = 'gpt-4o-mini';
  static String deepSeekModel = 'deepseek-chat'; // DeepSeek-V3
}
