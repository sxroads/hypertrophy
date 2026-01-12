import 'package:flutter/material.dart';
import 'package:hypertrophy/pages/register_page.dart';
import 'package:hypertrophy/pages/home_page.dart';
import 'package:hypertrophy/services/auth_service.dart';
import 'package:hypertrophy/services/anonymous_user_service.dart';
import 'package:hypertrophy/services/storage_clear_service.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'package:hypertrophy/services/sync_service.dart';
import 'package:hypertrophy/services/event_queue_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _authService = AuthService();
  final _anonymousUserService = AnonymousUserService();
  final _apiService = ApiService();
  final _syncService = SyncService();
  final _eventQueueService = EventQueueService();
  String? _anonymousUserId;
  String? _userGender;
  int? _userAge;
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _authService.addListener(_onAuthChange);
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    setState(() {});
  }

  Future<void> _loadUserData() async {
    final anonymousId = await _anonymousUserService.getAnonymousUserId();

    // Load user profile if authenticated
    if (_authService.isAuthenticated && _authService.token != null) {
      try {
        final userInfo = await _apiService.getCurrentUserInfo(
          token: _authService.token!,
        );
        if (mounted) {
          setState(() {
            _userGender = userInfo['gender'] as String?;
            _userAge = userInfo['age'] as int?;
          });
        }
      } catch (e) {
        debugPrint('Failed to load user info: $e');
      }
    }

    if (mounted) {
      setState(() {
        _anonymousUserId = anonymousId;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncPendingEvents() async {
    if (_isSyncing) {
      return; // Already syncing
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final deviceId = await _anonymousUserService.getOrCreateDeviceId();
      final userId = await _authService.getCurrentUserId();

      final syncResult = await _syncService.syncPendingEvents(
        deviceId: deviceId,
        userId: userId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncResult.message),
            backgroundColor: syncResult.isSuccess
                ? Colors.green
                : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _showQueueStats() async {
    try {
      final stats = await _eventQueueService.getQueueStats();

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.queue, color: Colors.blue),
                SizedBox(width: 8),
                Text('Event Queue Statistics'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatRow('Pending', stats['pending'] ?? 0, Colors.orange),
                const SizedBox(height: 12),
                _buildStatRow('Syncing', stats['syncing'] ?? 0, Colors.blue),
                const SizedBox(height: 12),
                _buildStatRow('Failed', stats['failed'] ?? 0, Colors.red),
                const Divider(height: 24),
                _buildStatRow('Total', stats['total'] ?? 0, Colors.grey),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading queue stats: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatRow(String label, int value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // User Status Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _authService.isAuthenticated
                                    ? Icons.check_circle
                                    : Icons.person_outline,
                                color: _authService.isAuthenticated
                                    ? Colors.green
                                    : Colors.orange,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 16),

                                    // User ID Card
                                    Text(
                                      _authService.isAuthenticated
                                          ? 'Authenticated'
                                          : 'Anonymous User',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _authService.isAuthenticated
                                          ? 'You are logged in'
                                          : 'Using app anonymously',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_authService.isAuthenticated) ...[
                    const SizedBox(height: 16),
                    // Email Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Email',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _authService.email ?? 'N/A',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Profile Information Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Profile Information',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: _showEditProfileDialog,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildProfileField(
                              'Gender',
                              _userGender ?? 'Not set',
                            ),
                            const SizedBox(height: 8),
                            _buildProfileField(
                              'Age',
                              _userAge?.toString() ?? 'Not set',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (!_authService.isAuthenticated &&
                      _anonymousUserId != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Anonymous User',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You are using the app anonymously. Log in to merge your workout data to your account.',
                              style: TextStyle(
                                color: Colors.blue.shade900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  //// Sync Button
                  //ElevatedButton.icon(
                  //  onPressed: _isSyncing ? null : _syncPendingEvents,
                  //  icon: _isSyncing
                  //      ? const SizedBox(
                  //          width: 20,
                  //          height: 20,
                  //          child: CircularProgressIndicator(strokeWidth: 2),
                  //        )
                  //      : const Icon(Icons.sync),
                  //  label: Text(
                  //    _isSyncing ? 'Syncing...' : 'Sync Pending Events',
                  //  ),
                  //  style: ElevatedButton.styleFrom(
                  //    padding: const EdgeInsets.symmetric(vertical: 16),
                  //  ),
                  //),
                  //const SizedBox(height: 16),
                  //// Queue Stats Button
                  //OutlinedButton.icon(
                  //  onPressed: _showQueueStats,
                  //  icon: const Icon(Icons.queue),
                  //  label: const Text('Show Queue Statistics'),
                  //  style: OutlinedButton.styleFrom(
                  //    padding: const EdgeInsets.symmetric(vertical: 16),
                  //  ),
                  //),
                  //const SizedBox(height: 16),
                  //// Action Buttons
                  if (_authService.isAuthenticated)
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _authService.logout();
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const HomePage(),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RegisterPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.login),
                      label: const Text('Login'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Clear All Data Button (for development/testing)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear All Local Data?'),
                          content: const Text(
                            'This will delete all local data including:\n'
                            '• Auth tokens and user IDs\n'
                            '• Anonymous user IDs\n'
                            '• Event queue\n'
                            '• Templates\n\n'
                            'This action cannot be undone. Continue?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Clear All'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true && context.mounted) {
                        try {
                          await StorageClearService.clearAllLocalData();
                          await _authService.logout();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('All local data cleared'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (context) => const HomePage(),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error clearing data: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear All Local Data'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileField(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }

  void _showEditProfileDialog() {
    String? selectedGender = _userGender;
    final ageController = TextEditingController(
      text: _userAge?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Profile'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedGender,
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedGender = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: ageController,
                    decoration: const InputDecoration(
                      labelText: 'Age',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final token = _authService.token;
                      if (token != null) {
                        await _apiService.updateUserProfile(
                          token: token,
                          gender: selectedGender,
                          age: ageController.text.isNotEmpty
                              ? int.parse(ageController.text)
                              : null,
                        );
                        await _loadUserData();
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile updated successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      }
                    } catch (e) {
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
