import 'package:flutter/foundation.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;

import 'fitness_chat_context_service.dart';
import 'local_llm_runtime_service.dart';
import 'model_storage_service.dart';

const String _fitnessSystemPrompt = '''
You are Tempo Coach, an offline personal fitness and wellness assistant inside the Tempo app.
Give practical, concise, actionable guidance on workouts, nutrition, recovery, sleep, and goal tracking.
Use the supplied user context when referring to personal data and never invent metrics.
Do not give medical diagnoses or prescribe medication.
''';

const String _genericChatFailureReply =
    'Unable to generate a fitness reply right now. Please try again in a moment.';

enum FitnessChatRole { user, assistant }

class FitnessChatTurn {
  const FitnessChatTurn({
    required this.role,
    required this.content,
  });

  final FitnessChatRole role;
  final String content;
}

class FitnessChatService {
  FitnessChatService({
    ModelStorageService? modelStorageService,
    FitnessChatContextService? contextService,
    LocalLlmRuntimeService? runtimeService,
  })  : _modelStorageService = modelStorageService ?? ModelStorageService(),
        _contextService = contextService ?? FitnessChatContextService(),
        _runtimeService = runtimeService ?? LocalLlmRuntimeService.instance;

  final ModelStorageService _modelStorageService;
  final FitnessChatContextService _contextService;
  final LocalLlmRuntimeService _runtimeService;

  ValueNotifier<LocalLlmRuntimeStatus> get runtimeStatus =>
      _runtimeService.status;

  bool get isHostedChatEnabled => false;

  Future<ModelLocationState> getModelLocation() {
    return _modelStorageService.getModelLocation();
  }

  Future<ModelLocationState> prepareModel() async {
    final location = await _modelStorageService.getModelLocation();
    final modelPath = location.path;
    if (!kIsWeb && location.exists && modelPath != null) {
      await _runtimeService.ensureModelLoaded(modelPath);
    } else {
      await _runtimeService.unloadModel();
    }
    return location;
  }

  Future<ModelLocationState> pickModelFile() async {
    await _modelStorageService.pickModelFile();
    return prepareModel();
  }

  Future<ModelLocationState> clearSavedModelPath() async {
    await _modelStorageService.clearModelPath();
    return prepareModel();
  }

  Future<void> stopGeneration() => _runtimeService.stopGeneration();

  Stream<String> streamMessage({
    required String userMessage,
    required List<FitnessChatTurn> history,
  }) async* {
    if (userMessage.trim().isEmpty) return;

    final context = await _contextService.buildContext();
    final chatMessages = _buildChatMessages(
      context: context,
      userMessage: userMessage,
      history: history,
    );

    if (!kIsWeb) {
      final modelLocation = await _modelStorageService.getModelLocation();
      final modelPath = modelLocation.path;
      if (modelLocation.exists && modelPath != null) {
        final messages = chatMessages
            .map(
              (m) => llama.ChatMessage(
                role: m['role'] ?? 'user',
                content: m['content'] ?? '',
              ),
            )
            .toList(growable: false);
        try {
          yield* _runtimeService.generateChat(
            modelPath: modelPath,
            messages: messages,
          );
          return;
        } catch (error) {
          debugPrint('Local mobile LLM failed, using offline coach fallback: $error');
        }
      }
    }

    yield _offlineCoachReply(userMessage, context);
  }

  String _offlineCoachReply(String query, FitnessChatContext ctx) {
    final q = query.toLowerCase();
    final namePrefix =
        ctx.displayName != null ? '${ctx.displayName}, ' : '';

    if (q.contains('bmi') || q.contains('weight') || q.contains('stats')) {
      return '${namePrefix}here is your local profile snapshot:\n'
          '• **Primary Goal:** ${ctx.goalLabel}\n'
          '${ctx.summaryLines.map((l) => '• $l').join('\n')}\n\n'
          'Update your weight, waist, or sleep anytime from the **Summary** tab.';
    }
    if (q.contains('sleep') || q.contains('recover')) {
      return '${namePrefix}for strong recovery aim for **7–9 hours of sleep**, stay hydrated, and schedule at least 1–2 active recovery or mobility days per week.';
    }
    if (q.contains('protein') || q.contains('diet') || q.contains('calor')) {
      return '${namePrefix}for your **${ctx.goalLabel}** goal:\n'
          '• Aim for **1.6–2.0 g protein per kg** of body weight daily.\n'
          '• Build meals around lean protein, whole grains, vegetables, and healthy fats.\n'
          '• Keep consistent meal timing around your workouts.';
    }
    if (q.contains('workout') || q.contains('plan') || q.contains('routine')) {
      return '${namePrefix}for **${ctx.goalLabel}**, check the **Workout** tab to follow a guided Fitness Journey or focus on 3–4 weekly sessions combining compound strength moves and 20–30 minutes of cardio.';
    }
    return '${namePrefix}I am running **100% offline** in Tempo! Ask me about your **stats**, **workouts**, **calories & nutrition**, or **sleep & recovery** (or load a local GGUF model in chat settings for full on-device AI).';
  }

  List<Map<String, String>> _buildChatMessages({
    required FitnessChatContext context,
    required String userMessage,
    required List<FitnessChatTurn> history,
  }) {
    final trimmed = history.where((t) => t.content.trim().isNotEmpty).toList();
    final recent = trimmed.length <= 8
        ? trimmed
        : trimmed.sublist(trimmed.length - 8);
    return [
      {
        'role': 'system',
        'content': '$_fitnessSystemPrompt\n\n${context.toPromptBlock()}',
      },
      ...recent.map(
        (t) => {
          'role': t.role == FitnessChatRole.user ? 'user' : 'assistant',
          'content': t.content,
        },
      ),
      {'role': 'user', 'content': userMessage},
    ];
  }

  String get genericChatFailureReply => _genericChatFailureReply;
}
