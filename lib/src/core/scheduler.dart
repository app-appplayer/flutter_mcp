import 'dart:async';
import '../config/job.dart';
import '../utils/logger.dart';

/// MCP 작업 스케줄러
class MCPScheduler {
  /// 등록된 작업
  final Map<String, MCPJob> _jobs = {};

  /// 타이머
  Timer? _timer;

  /// 실행 중 여부
  bool _isRunning = false;

  /// 로거
  final MCPLogger _logger = MCPLogger('mcp.scheduler');

  /// 실행 중 여부
  bool get isRunning => _isRunning;

  /// 스케줄러 초기화
  void initialize() {
    _logger.debug('스케줄러 초기화');
  }

  /// 작업 추가
  String addJob(MCPJob job) {
    final jobId = job.id ?? 'job_${DateTime.now().millisecondsSinceEpoch}_${_jobs.length}';
    _jobs[jobId] = job.copyWith(id: jobId);
    _logger.debug('작업 추가: $jobId, 간격: ${job.interval}');
    return jobId;
  }

  /// 작업 제거
  void removeJob(String jobId) {
    _logger.debug('작업 제거: $jobId');
    _jobs.remove(jobId);
  }

  /// 스케줄러 시작
  void start() {
    if (_isRunning) return;

    _logger.debug('스케줄러 시작');
    _timer = Timer.periodic(Duration(seconds: 1), _checkJobs);
    _isRunning = true;
  }

  /// 스케줄러 중지
  void stop() {
    _logger.debug('스케줄러 중지');
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  /// 작업 실행 확인
  void _checkJobs(Timer timer) {
    final now = DateTime.now();

    for (final entry in _jobs.entries.toList()) {
      final jobId = entry.key;
      final job = entry.value;

      if (job.lastRun == null ||
          now.difference(job.lastRun!) >= job.interval) {
        // 작업 실행
        _executeJob(jobId, job, now);
      }
    }
  }

  /// 작업 실행
  void _executeJob(String jobId, MCPJob job, DateTime now) {
    _logger.debug('작업 실행: $jobId');

    try {
      job.task();
      // 마지막 실행 시간 업데이트
      _jobs[jobId] = job.copyWith(lastRun: now);

      // 일회성 작업은 제거
      if (job.runOnce) {
        _logger.debug('일회성 작업 제거: $jobId');
        _jobs.remove(jobId);
      }
    } catch (e, stackTrace) {
      _logger.error('작업 실행 오류: $jobId', e, stackTrace);
    }
  }
}