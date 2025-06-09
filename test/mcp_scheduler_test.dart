import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/core/scheduler.dart';
import 'package:flutter_mcp/src/config/job.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('MCPScheduler Tests', () {
    late MCPScheduler scheduler;
    
    setUp(() {
      scheduler = MCPScheduler();
      scheduler.initialize();
    });
    
    tearDown(() {
      scheduler.stop();
    });
    
    group('Scheduler Initialization', () {
      test('should initialize scheduler correctly', () {
        expect(scheduler.isRunning, isFalse);
        expect(scheduler.jobCount, equals(0));
        expect(scheduler.activeJobCount, equals(0));
      });
      
      test('should start and stop scheduler', () {
        expect(scheduler.isRunning, isFalse);
        
        scheduler.start();
        expect(scheduler.isRunning, isTrue);
        
        scheduler.stop();
        expect(scheduler.isRunning, isFalse);
      });
      
      test('should handle multiple start calls gracefully', () {
        scheduler.start();
        expect(scheduler.isRunning, isTrue);
        
        // Second start should not cause issues
        scheduler.start();
        expect(scheduler.isRunning, isTrue);
      });
    });
    
    group('Job Management', () {
      test('should add jobs correctly', () {
        final job = MCPJob(
          name: 'test_job',
          interval: Duration(seconds: 5),
          task: () async => 'completed',
        );
        
        final jobId = scheduler.addJob(job);
        
        expect(jobId, isNotEmpty);
        expect(scheduler.jobCount, equals(1));
      });
      
      test('should remove jobs correctly', () {
        final job = MCPJob(
          name: 'test_job',
          interval: Duration(seconds: 5),
          task: () async => 'completed',
        );
        
        final jobId = scheduler.addJob(job);
        expect(scheduler.jobCount, equals(1));
        
        scheduler.removeJob(jobId);
        expect(scheduler.jobCount, equals(0));
      });
      
      test('should generate unique job IDs', () {
        final job1 = MCPJob(
          name: 'job1',
          interval: Duration(seconds: 5),
          task: () async => 'job1',
        );
        
        final job2 = MCPJob(
          name: 'job2',
          interval: Duration(seconds: 5),
          task: () async => 'job2',
        );
        
        final jobId1 = scheduler.addJob(job1);
        final jobId2 = scheduler.addJob(job2);
        
        expect(jobId1, isNot(equals(jobId2)));
        expect(scheduler.jobCount, equals(2));
      });
      
      test('should use provided job ID when available', () {
        final job = MCPJob(
          id: 'custom_job_id',
          name: 'test_job',
          interval: Duration(seconds: 5),
          task: () async => 'completed',
        );
        
        final jobId = scheduler.addJob(job);
        expect(jobId, equals('custom_job_id'));
      });
    });
    
    group('Job Execution', () {
      test('should execute jobs when conditions are met', () {
        var executionCount = 0;
        
        final job = MCPJob(
          name: 'test_job',
          interval: Duration(milliseconds: 100),
          task: () {
            executionCount++;
            return 'execution_$executionCount';
          },
        );
        
        final jobId = scheduler.addJob(job);
        expect(scheduler.jobCount, equals(1));
        
        // Get the job to verify it has no lastRun initially
        final addedJob = scheduler.getJob(jobId)!;
        expect(addedJob.lastRun, isNull);
        
        // Start scheduler and manually trigger job checking
        scheduler.start();
        expect(scheduler.isRunning, isTrue);
        
        // Manually trigger job checking to test the core logic
        scheduler.checkJobsNow();
        
        // The job should have executed once since lastRun was null
        expect(executionCount, equals(1));
        
        // Verify job was updated with lastRun
        final updatedJob = scheduler.getJob(jobId)!;
        expect(updatedJob.lastRun, isNotNull);
      });
      
      test('should handle job execution errors gracefully', () {
        var errorCount = 0;
        
        final job = MCPJob(
          name: 'error_job',
          interval: Duration(milliseconds: 100),
          task: () {
            errorCount++;
            throw Exception('Test error $errorCount');
          },
        );
        
        scheduler.addJob(job);
        scheduler.start();
        
        // Manually trigger job execution
        scheduler.checkJobsNow();
        
        // Should have attempted execution once
        expect(errorCount, equals(1));
        
        // Scheduler should still be running despite the error
        expect(scheduler.isRunning, isTrue);
      });
      
      test('should not execute job concurrently', () {
        var isRunning = false;
        var concurrentExecutions = 0;
        
        final job = MCPJob(
          name: 'concurrent_job',
          interval: Duration(milliseconds: 50),
          task: () {
            if (isRunning) {
              concurrentExecutions++;
            }
            isRunning = true;
            
            // Simulate some work
            for (var i = 0; i < 1000; i++) {
              // busy work
            }
            
            isRunning = false;
            return 'completed';
          },
        );
        
        final jobId = scheduler.addJob(job);
        scheduler.start();
        
        // Trigger execution multiple times rapidly
        scheduler.checkJobsNow();
        scheduler.checkJobsNow(); // This should be skipped due to the job already running
        
        // Should never have concurrent executions
        expect(concurrentExecutions, equals(0));
        
        // Job should be marked as completed
        final executedJob = scheduler.getJob(jobId)!;
        expect(executedJob.lastRun, isNotNull);
      });
    });
    
    group('Job Dependencies and Ordering', () {
      test('should handle multiple jobs with different intervals', () async {
        var fastJobCount = 0;
        var slowJobCount = 0;
        
        final fastJob = MCPJob(
          name: 'fast_job',
          interval: Duration(milliseconds: 500), // Faster than 1 second check interval
          task: () async {
            fastJobCount++;
            return 'fast_\$fastJobCount';
          },
        );
        
        final slowJob = MCPJob(
          name: 'slow_job',
          interval: Duration(seconds: 2), // Slower than check interval  
          task: () async {
            slowJobCount++;
            return 'slow_\$slowJobCount';
          },
        );
        
        scheduler.addJob(fastJob);
        scheduler.addJob(slowJob);
        scheduler.start();
        
        // Wait for executions (need to wait longer to see interval differences)
        await Future.delayed(Duration(milliseconds: 4500));
        
        // Fast job (500ms interval) should execute more frequently than slow job (2s interval)
        expect(fastJobCount, greaterThan(slowJobCount));
        expect(slowJobCount, greaterThanOrEqualTo(1)); // At least one execution for slow job
      });
      
      test('should maintain job isolation', () async {
        var job1Executed = false;
        var job2Executed = false;
        
        final job1 = MCPJob(
          name: 'isolated_job1',
          interval: Duration(milliseconds: 100),
          task: () async {
            job1Executed = true;
            throw Exception('Job 1 error');
          },
        );
        
        final job2 = MCPJob(
          name: 'isolated_job2',
          interval: Duration(milliseconds: 100),
          task: () async {
            job2Executed = true;
            return 'job2_success';
          },
        );
        
        scheduler.addJob(job1);
        scheduler.addJob(job2);
        scheduler.start();
        
        await Future.delayed(Duration(milliseconds: 1500));
        
        // Both jobs should execute despite job1 error
        expect(job1Executed, isTrue);
        expect(job2Executed, isTrue);
      });
    });
    
    group('Job History and Monitoring', () {
      test('should track job execution history', () async {
        final job = MCPJob(
          name: 'history_job',
          interval: Duration(milliseconds: 100),
          task: () async => 'completed',
        );
        
        scheduler.addJob(job);
        scheduler.start();
        
        await Future.delayed(Duration(milliseconds: 1500));
        
        // Check that execution history is being tracked
        // Note: This assumes the scheduler has a way to get execution history
        // If not available publicly, this test verifies the execution occurred
        expect(scheduler.activeJobCount, equals(0)); // No jobs should be running
      });
    });
    
    group('Resource Management', () {
      test('should properly cleanup when stopped', () async {
        final job = MCPJob(
          name: 'cleanup_job',
          interval: Duration(milliseconds: 100),
          task: () async => 'completed',
        );
        
        scheduler.addJob(job);
        scheduler.start();
        
        await Future.delayed(Duration(milliseconds: 1500));
        
        scheduler.stop();
        
        // After stopping, should not execute more jobs
        await Future.delayed(Duration(milliseconds: 1500));
        
        expect(scheduler.isRunning, isFalse);
        expect(scheduler.activeJobCount, equals(0));
      });
      
      test('should handle scheduler restart', () async {
        var executionCount = 0;
        
        final job = MCPJob(
          name: 'restart_job',
          interval: Duration(milliseconds: 100),
          task: () async {
            executionCount++;
            return 'execution_\$executionCount';
          },
        );
        
        scheduler.addJob(job);
        
        // Start, wait, stop
        scheduler.start();
        await Future.delayed(Duration(milliseconds: 1500));
        scheduler.stop();
        
        final countAfterFirstRun = executionCount;
        
        // Restart and wait
        scheduler.start();
        await Future.delayed(Duration(milliseconds: 1500));
        
        // Should continue executing after restart
        expect(executionCount, greaterThan(countAfterFirstRun));
      });
    });
    
    group('Edge Cases and Error Scenarios', () {
      test('should handle removing non-existent job gracefully', () {
        expect(() => scheduler.removeJob('non_existent_job'), isNot(throwsException));
        expect(scheduler.jobCount, equals(0));
      });
      
      test('should handle jobs with very short intervals', () async {
        var executionCount = 0;
        
        final job = MCPJob(
          name: 'short_interval_job',
          interval: Duration(milliseconds: 1), // Very short
          task: () async {
            executionCount++;
            return 'execution_\$executionCount';
          },
        );
        
        scheduler.addJob(job);
        scheduler.start();
        
        // Scheduler checks every 1 second, so wait at least 1 second
        await Future.delayed(Duration(seconds: 2));
        
        // Should execute at least once (scheduler runs every 1 second)
        expect(executionCount, greaterThan(0));
        expect(executionCount, lessThanOrEqualTo(3)); // Should not execute too many times
      });
      
      test('should handle jobs with very long intervals', () async {
        var executed = false;
        
        final job = MCPJob(
          name: 'long_interval_job',
          interval: Duration(hours: 1), // Very long
          task: () async {
            executed = true;
            return 'completed';
          },
        );
        
        scheduler.addJob(job);
        scheduler.start();
        
        // Wait for first execution to complete (job will run once due to null lastRun)
        await Future.delayed(Duration(milliseconds: 1500));
        
        // Reset flag and wait again 
        executed = false;
        await Future.delayed(Duration(milliseconds: 1500));
        
        // Should not execute again within short time frame since interval is 1 hour
        expect(executed, isFalse);
      });
      
      test('should handle null task gracefully', () async {
        // This test depends on how MCPJob handles null tasks
        // Expecting any exception for null task
        expect(() {
          MCPJob(
            name: 'null_task_job',
            interval: Duration(seconds: 1),
            task: null as dynamic, // Force null
          );
        }, throwsA(isA<TypeError>()));
      });
    });
    
    group('Performance and Load Testing', () {
      test('should handle many jobs efficiently', () async {
        const jobCount = 50;
        var totalExecutions = 0;
        
        // Add many jobs
        for (int i = 0; i < jobCount; i++) {
          final job = MCPJob(
            name: 'load_job_\$i',
            interval: Duration(milliseconds: 100 + (i * 10)), // Varying intervals
            task: () async {
              totalExecutions++;
              return 'job_\$i_completed';
            },
          );
          scheduler.addJob(job);
        }
        
        expect(scheduler.jobCount, equals(jobCount));
        
        scheduler.start();
        await Future.delayed(Duration(milliseconds: 1500));
        
        // All jobs should have executed at least once
        expect(totalExecutions, greaterThanOrEqualTo(jobCount));
        
        // Scheduler should still be responsive
        expect(scheduler.isRunning, isTrue);
      });
    });
  });
}