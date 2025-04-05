/// MCP 작업 스케줄 클래스
class MCPJob {
  /// 작업 ID
  final String? id;

  /// 작업 실행 간격
  final Duration interval;

  /// 실행할 작업 함수
  final Function() task;

  /// 일회성 작업 여부
  final bool runOnce;

  /// 마지막 실행 시간
  final DateTime? lastRun;

  MCPJob({
    this.id,
    required this.interval,
    required this.task,
    this.runOnce = false,
    this.lastRun,
  });

  /// 작업 복사본 생성
  MCPJob copyWith({
    String? id,
    Duration? interval,
    Function()? task,
    bool? runOnce,
    DateTime? lastRun,
  }) {
    return MCPJob(
      id: id ?? this.id,
      interval: interval ?? this.interval,
      task: task ?? this.task,
      runOnce: runOnce ?? this.runOnce,
      lastRun: lastRun ?? this.lastRun,
    );
  }

  /// 정기적 실행 작업 생성
  factory MCPJob.every(Duration interval, {required Function() task}) {
    return MCPJob(
      interval: interval,
      task: task,
    );
  }

  /// 일회성 작업 생성
  factory MCPJob.once(Duration delay, {required Function() task}) {
    return MCPJob(
      interval: delay,
      task: task,
      runOnce: true,
    );
  }
}