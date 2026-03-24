import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/server_config.dart';
import '../../data/server_providers/server_detector.dart';
import '../../services/cloud_login_service.dart';
import '../../services/discovery_service.dart';
import '../../state/auth_provider.dart';

/// Which connection method the user chose on page 1.
enum _ConnectionMethod { manual, scan, embyConnect, plex }

/// Full-screen multi-page wizard that replaces AddServerSheet and
/// CloudLoginSheet.  Uses a [PageController] for smooth horizontal
/// transitions between steps.
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _pageController = PageController();

  // ── Shared state ──────────────────────────────────────────────
  _ConnectionMethod? _method;
  String _stepTitle = 'Connect';
  String? _error;

  // ── Manual URL state (Page 2a) ────────────────────────────────
  final _urlController = TextEditingController();
  ServerDetectionResult? _detectedServer;
  bool _isDetecting = false;
  bool _httpAcknowledged = false;

  // ── Network scan state (Page 2b) ──────────────────────────────
  final _discoveryService = DiscoveryService();
  final _discoveredServers = <DiscoveredServer>[];
  StreamSubscription<DiscoveredServer>? _discoverySub;
  bool _isScanning = false;

  // ── Emby Connect state (Page 2c / 2d) ─────────────────────────
  final _cloudLoginService = CloudLoginService();
  final _embyUsernameController = TextEditingController();
  final _embyPasswordController = TextEditingController();
  final _embyFormKey = GlobalKey<FormState>();
  bool _embyLoginInProgress = false;
  bool _obscureEmbyPassword = true;

  // ── Cloud server selection (Page 2d) ──────────────────────────
  List<CloudServer> _cloudServers = [];
  bool _isFetchingServers = false;
  ServerType? _cloudProviderType;

  // ── Plex state (Page 2e) ──────────────────────────────────────
  int? _plexPinId;
  String? _plexCode;
  String? _plexAuthToken;
  Timer? _plexPollTimer;
  bool _plexAuthInProgress = false;

  // ── Login state (Page 3) ──────────────────────────────────────
  final _loginFormKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isConnecting = false;
  bool _obscureLoginPassword = true;

  // ── Lifecycle ─────────────────────────────────────────────────

  @override
  void dispose() {
    _pageController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _embyUsernameController.dispose();
    _embyPasswordController.dispose();
    _discoverySub?.cancel();
    _discoveryService.dispose();
    _plexPollTimer?.cancel();
    _cloudLoginService.dispose();
    super.dispose();
  }

  // ── Navigation helpers ────────────────────────────────────────

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _goBack() {
    final currentPage = _pageController.page?.round() ?? 0;
    if (currentPage == 0) {
      Navigator.pop(context);
    } else {
      // Clean up any in-progress operations when going back
      _cancelPlexAuth(silent: true);
      _discoverySub?.cancel();
      setState(() {
        _isScanning = false;
        _error = null;
      });
      _goToPage(0);
      setState(() => _stepTitle = 'Connect');
    }
  }

  // ── Page 1: Method selection ──────────────────────────────────

  void _selectMethod(_ConnectionMethod method) {
    _method = method;
    setState(() => _error = null);
    switch (method) {
      case _ConnectionMethod.manual:
        setState(() => _stepTitle = 'Enter Server URL');
        _goToPage(1);
      case _ConnectionMethod.scan:
        setState(() => _stepTitle = 'Scan Network');
        _startNetworkScan();
        _goToPage(1);
      case _ConnectionMethod.embyConnect:
        setState(() => _stepTitle = 'Emby Connect');
        _goToPage(1);
      case _ConnectionMethod.plex:
        setState(() => _stepTitle = 'Plex');
        _startPlexAuth();
        _goToPage(1);
    }
  }

  // ── Page 2a: Manual URL detection ─────────────────────────────

  Future<void> _detectServer() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final authService = ref.read(authServiceProvider);
    try {
      authService.validateUrl(url, httpAcknowledged: _httpAcknowledged);
    } on InsecureConnectionException {
      final confirmed = await _showHttpWarning(url);
      if (confirmed != true) return;
      _httpAcknowledged = true;
    }

    setState(() {
      _isDetecting = true;
      _error = null;
      _detectedServer = null;
    });

    try {
      final result = await authService.detectServer(url);
      setState(() {
        _detectedServer = result;
        _isDetecting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not detect server. Check the URL.';
        _isDetecting = false;
      });
    }
  }

  void _goToLoginFromManual() {
    if (_detectedServer == null) return;
    setState(() => _stepTitle = 'Sign In');
    _goToPage(2);
  }

  Future<bool?> _showHttpWarning(String url) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insecure Connection'),
        content: Text(
          url.isLocalNetwork
              ? 'Connecting via HTTP on a local network. Credentials will be '
                    'sent unencrypted.'
              : 'WARNING: Connecting to a public server via HTTP. Your '
                    'credentials can be intercepted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Connect Anyway'),
          ),
        ],
      ),
    );
  }

  // ── Page 2b: Network scan ─────────────────────────────────────

  void _startNetworkScan() {
    _discoverySub?.cancel();
    setState(() {
      _discoveredServers.clear();
      _isScanning = true;
      _error = null;
    });

    _discoverySub = _discoveryService.discover().listen(
      (server) {
        if (mounted) {
          setState(() {
            if (!_discoveredServers.any((s) => s.url == server.url)) {
              _discoveredServers.add(server);
            }
          });
        }
      },
      onDone: () {
        if (mounted) setState(() => _isScanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _isScanning = false);
      },
    );
  }

  void _selectDiscoveredServer(DiscoveredServer server) {
    _urlController.text = server.url;
    setState(() {
      _detectedServer = ServerDetectionResult(
        type: server.type,
        serverName: server.name,
        version: server.version,
      );
      _stepTitle = 'Sign In';
    });
    _goToPage(2);
  }

  // ── Page 2c: Emby Connect ─────────────────────────────────────

  Future<void> _startEmbyLogin() async {
    if (!_embyFormKey.currentState!.validate()) return;

    setState(() {
      _embyLoginInProgress = true;
      _error = null;
    });

    try {
      final result = await _cloudLoginService.loginEmbyConnect(
        username: _embyUsernameController.text.trim(),
        password: _embyPasswordController.text,
      );

      if (!mounted) return;

      _cloudProviderType = ServerType.emby;
      await _fetchEmbyServers(
        connectToken: result['accessToken']!,
        userId: result['userId']!,
      );
    } on DioException catch (e) {
      if (mounted) {
        final status = e.response?.statusCode;
        final message = status == 401
            ? 'Invalid username or password.'
            : status == 400
            ? 'Invalid request. Please check your email/username format.'
            : 'Could not reach Emby Connect. Check your internet connection.';
        setState(() {
          _error = message;
          _embyLoginInProgress = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('Authentication failed')
              ? 'Invalid username or password. Please try again.'
              : 'Login failed. Please try again.';
          _embyLoginInProgress = false;
        });
      }
    }
  }

  Future<void> _fetchEmbyServers({
    required String connectToken,
    required String userId,
  }) async {
    setState(() => _isFetchingServers = true);

    try {
      final servers = await _cloudLoginService.fetchEmbyServers(
        connectToken: connectToken,
        userId: userId,
      );

      if (mounted) {
        setState(() {
          _cloudServers = servers;
          _isFetchingServers = false;
          _embyLoginInProgress = false;
          _stepTitle = 'Select Server';
          // Stay on page 1 (the build method will show server list)
          _method = _ConnectionMethod.embyConnect;
        });
        // Move to the cloud server selection page (page index 1 is reused)
        _goToPage(1);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to fetch servers. Please try again.';
          _isFetchingServers = false;
          _embyLoginInProgress = false;
        });
      }
    }
  }

  // ── Page 2e: Plex OAuth ───────────────────────────────────────

  Future<void> _startPlexAuth() async {
    setState(() {
      _plexAuthInProgress = true;
      _cloudProviderType = ServerType.plex;
      _error = null;
    });

    try {
      final pin = await _cloudLoginService.requestPlexPin();
      _plexPinId = pin['id'] as int;
      _plexCode = pin['code'] as String;

      final authUrl = _cloudLoginService.getPlexAuthUrl(_plexCode!);
      final uri = Uri.parse(authUrl);

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          setState(() {
            _error = 'Could not open browser. Please try again.';
            _plexAuthInProgress = false;
          });
        }
        return;
      }

      _startPlexPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to start Plex authentication. Please try again.';
          _plexAuthInProgress = false;
        });
      }
    }
  }

  void _startPlexPolling() {
    _plexPollTimer?.cancel();
    _plexPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkPlexPin(),
    );
  }

  Future<void> _checkPlexPin() async {
    if (_plexPinId == null || !mounted) return;

    try {
      final token = await _cloudLoginService.checkPlexPin(_plexPinId!);
      if (token != null && mounted) {
        _plexPollTimer?.cancel();
        _plexAuthToken = token;
        await _fetchPlexServers();
      }
    } catch (_) {
      // Polling — silently retry on transient errors.
    }
  }

  Future<void> _fetchPlexServers() async {
    if (_plexAuthToken == null) return;

    setState(() {
      _isFetchingServers = true;
      _error = null;
    });

    try {
      final servers = await _cloudLoginService.fetchPlexServers(
        _plexAuthToken!,
      );

      if (mounted) {
        setState(() {
          _cloudServers = servers;
          _isFetchingServers = false;
          _plexAuthInProgress = false;
          _stepTitle = 'Select Server';
        });
        // Already on page 1; the build will show server list
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to fetch servers. Please try again.';
          _isFetchingServers = false;
          _plexAuthInProgress = false;
        });
      }
    }
  }

  void _cancelPlexAuth({bool silent = false}) {
    _plexPollTimer?.cancel();
    if (!silent) {
      setState(() {
        _plexAuthInProgress = false;
        _plexPinId = null;
        _plexCode = null;
        _error = null;
      });
    }
  }

  // ── Page 3: Login ─────────────────────────────────────────────

  Future<void> _connect() async {
    if (!_loginFormKey.currentState!.validate()) return;
    if (_detectedServer == null) return;

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      await ref
          .read(authNotifierProvider.notifier)
          .login(
            url: _urlController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            serverType: _detectedServer!.type,
            serverName: _detectedServer!.serverName,
          );

      if (!mounted) return;

      final authState = ref.read(authNotifierProvider);
      if (authState.isAuthenticated) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _error =
              authState.error ?? 'Login failed. Please check your credentials.';
          _isConnecting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isConnecting = false;
      });
    }
  }

  /// For cloud-authenticated servers (Plex/Emby Connect) that don't need
  /// a separate username/password step.
  Future<void> _addCloudServer(CloudServer server) async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      await ref
          .read(authNotifierProvider.notifier)
          .login(
            url: server.url,
            username: '',
            password: '',
            serverType: server.type,
            serverName: server.name,
          );

      if (!mounted) return;

      final authState = ref.read(authNotifierProvider);
      if (authState.isAuthenticated) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _error = authState.error ?? 'Could not add ${server.name}.';
          _isConnecting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not add ${server.name}. Please try again.';
        _isConnecting = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LibrettoTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
        title: Text(_stepTitle),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [_buildMethodPage(), _buildStep2Page(), _buildLoginPage()],
      ),
    );
  }

  // ── Page 1: Connection method cards ───────────────────────────

  Widget _buildMethodPage() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'How would you like to connect?',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a method to add your media server.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: LibrettoTheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        _MethodCard(
          icon: Icons.dns,
          title: 'Enter Server URL',
          subtitle: 'Manually type your server address',
          onTap: () => _selectMethod(_ConnectionMethod.manual),
        ),
        const SizedBox(height: 12),
        _MethodCard(
          icon: Icons.wifi_find,
          title: 'Scan Network',
          subtitle: 'Discover servers on your local network',
          onTap: () => _selectMethod(_ConnectionMethod.scan),
        ),
        const SizedBox(height: 12),
        _MethodCard(
          icon: Icons.cloud,
          title: 'Emby Connect',
          subtitle: 'Sign in with your Emby cloud account',
          onTap: () => _selectMethod(_ConnectionMethod.embyConnect),
        ),
        const SizedBox(height: 12),
        _MethodCard(
          icon: Icons.tv,
          title: 'Plex',
          subtitle: 'Sign in with your Plex account',
          onTap: () => _selectMethod(_ConnectionMethod.plex),
        ),
      ],
    );
  }

  // ── Page 2: Dynamic content based on method ───────────────────

  Widget _buildStep2Page() {
    return switch (_method) {
      _ConnectionMethod.manual => _buildManualUrlPage(),
      _ConnectionMethod.scan => _buildScanPage(),
      _ConnectionMethod.embyConnect =>
        _cloudServers.isNotEmpty
            ? _buildCloudServerListPage()
            : _buildEmbyCredentialsPage(),
      _ConnectionMethod.plex =>
        _cloudServers.isNotEmpty
            ? _buildCloudServerListPage()
            : _buildPlexAuthPage(),
      null => const SizedBox.shrink(),
    };
  }

  // ── Page 2a: Manual URL ───────────────────────────────────────

  Widget _buildManualUrlPage() {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Server Address', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Enter the URL of your media server.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: LibrettoTheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://your-server.com:8096',
            suffixIcon: _isDetecting
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _detectServer,
                    tooltip: 'Detect server',
                  ),
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
          onSubmitted: (_) => _detectServer(),
        ),
        const SizedBox(height: 16),

        // Detect button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isDetecting ? null : _detectServer,
            icon: _isDetecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar),
            label: const Text('Detect'),
          ),
        ),

        // Detection result
        if (_detectedServer != null) ...[
          const SizedBox(height: 16),
          _DetectedBadge(result: _detectedServer!),
        ],

        // Error
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(
            message: _error!,
            onDismiss: () => setState(() => _error = null),
          ),
        ],

        const SizedBox(height: 24),

        // Next button
        _BerryButton(
          label: 'Next',
          onPressed: _detectedServer != null ? _goToLoginFromManual : null,
        ),
      ],
    );
  }

  // ── Page 2b: Network scan ─────────────────────────────────────

  Widget _buildScanPage() {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (_isScanning) ...[
          const SizedBox(height: 16),
          const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Scanning your network...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: LibrettoTheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        if (_discoveredServers.isNotEmpty) ...[
          Text('Found on your network', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final server in _discoveredServers) ...[
            _DiscoveredServerCard(
              server: server,
              onTap: () => _selectDiscoveredServer(server),
            ),
            const SizedBox(height: 8),
          ],
        ],

        if (!_isScanning && _discoveredServers.isEmpty) ...[
          const SizedBox(height: 48),
          Center(
            child: Icon(
              Icons.wifi_find,
              size: 64,
              color: LibrettoTheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('No servers found', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Make sure your server is running and on the same network.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: LibrettoTheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(
            message: _error!,
            onDismiss: () => setState(() => _error = null),
          ),
        ],

        const SizedBox(height: 24),

        // Scan Again button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isScanning ? null : _startNetworkScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Scan Again'),
          ),
        ),
      ],
    );
  }

  // ── Page 2c: Emby Connect credentials ─────────────────────────

  Widget _buildEmbyCredentialsPage() {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Icon
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: LibrettoTheme.embyColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_circle_outline,
              color: LibrettoTheme.embyColor,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Sign in to Emby Connect',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 24),
        Form(
          key: _embyFormKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _embyUsernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username or email',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  enabled: !_embyLoginInProgress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter your username or email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _embyPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureEmbyPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setState(
                        () => _obscureEmbyPassword = !_obscureEmbyPassword,
                      ),
                    ),
                  ),
                  obscureText: _obscureEmbyPassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  enabled: !_embyLoginInProgress,
                  onFieldSubmitted: (_) => _startEmbyLogin(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter your password';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(
                    message: _error!,
                    onDismiss: () => setState(() => _error = null),
                  ),
                ],
                const SizedBox(height: 24),
                _BerryButton(
                  label: 'Sign In',
                  isLoading: _embyLoginInProgress,
                  onPressed: _embyLoginInProgress ? null : _startEmbyLogin,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Page 2d: Cloud server selection ────────────────────────────

  Widget _buildCloudServerListPage() {
    final theme = Theme.of(context);
    final providerLabel = _cloudProviderType == ServerType.plex
        ? 'Plex'
        : 'Emby';

    if (_cloudServers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 48,
              color: LibrettoTheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text('No servers found', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'No $providerLabel servers are linked to this account.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: LibrettoTheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('$providerLabel Servers', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${_cloudServers.length} server${_cloudServers.length == 1 ? '' : 's'} found on your account.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        if (_error != null) ...[
          _ErrorBanner(
            message: _error!,
            onDismiss: () => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
        ],

        for (final server in _cloudServers) ...[
          _CloudServerCard(
            server: server,
            isConnecting: _isConnecting,
            onTap: () => _addCloudServer(server),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  // ── Page 2e: Plex auth ────────────────────────────────────────

  Widget _buildPlexAuthPage() {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        // Icon
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: LibrettoTheme.plexColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.tv,
              color: LibrettoTheme.plexColor,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 24),

        if (_plexAuthInProgress && !_isFetchingServers) ...[
          Center(
            child: Text(
              'Opening Plex.tv in your browser...',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Waiting for authentication...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: LibrettoTheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (_plexCode != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: LibrettoTheme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _plexCode!,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    letterSpacing: 4,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Complete the sign-in in your browser, then return here.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: OutlinedButton(
              onPressed: () {
                _cancelPlexAuth();
                _goBack();
              },
              style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
              child: const Text('Cancel'),
            ),
          ),
        ],

        if (_isFetchingServers) ...[
          Center(
            child: Text(
              'Fetching your servers...',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 16),
          _ErrorBanner(
            message: _error!,
            onDismiss: () => setState(() => _error = null),
          ),
        ],
      ],
    );
  }

  // ── Page 3: Login ─────────────────────────────────────────────

  Widget _buildLoginPage() {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Server info badge
        if (_detectedServer != null) ...[
          _DetectedBadge(result: _detectedServer!),
          const SizedBox(height: 8),
          Text(
            _urlController.text.trim(),
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],

        Text('Sign in to your server', style: theme.textTheme.titleLarge),
        const SizedBox(height: 24),

        Form(
          key: _loginFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                autocorrect: false,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter your username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureLoginPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () => setState(
                      () => _obscureLoginPassword = !_obscureLoginPassword,
                    ),
                  ),
                ),
                obscureText: _obscureLoginPassword,
                onFieldSubmitted: (_) => _connect(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter your password';
                  }
                  return null;
                },
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
              ],

              const SizedBox(height: 24),

              _BerryButton(
                label: 'Connect',
                isLoading: _isConnecting,
                onPressed: _isConnecting || _detectedServer == null
                    ? null
                    : _connect,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Private widget components
// ══════════════════════════════════════════════════════════════════

/// A big friendly card for the connection-method chooser (Page 1).
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      splashColor: LibrettoTheme.primary.withValues(alpha: 0.15),
      highlightColor: LibrettoTheme.primary.withValues(alpha: 0.08),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: LibrettoTheme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: LibrettoTheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: LibrettoTheme.primary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: LibrettoTheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Berry gradient pill button used for primary actions throughout the wizard.
class _BerryButton extends StatelessWidget {
  const _BerryButton({
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [LibrettoTheme.primary, LibrettoTheme.primaryVariant],
                )
              : null,
          color: enabled ? null : LibrettoTheme.cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: enabled
                ? LibrettoTheme.onPrimary
                : LibrettoTheme.onSurfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}

/// Shows the detected server info as a coloured badge.
class _DetectedBadge extends StatelessWidget {
  const _DetectedBadge({required this.result});

  final ServerDetectionResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LibrettoTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LibrettoTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle,
            color: LibrettoTheme.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${result.serverName} — ${result.type.name.toUpperCase()}'
              '${result.version != null ? ' v${result.version}' : ''}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline error banner.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LibrettoTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LibrettoTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: LibrettoTheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: LibrettoTheme.error),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// A card for a discovered LAN server.
class _DiscoveredServerCard extends StatelessWidget {
  const _DiscoveredServerCard({required this.server, required this.onTap});

  final DiscoveredServer server;
  final VoidCallback onTap;

  IconData _iconForType(ServerType type) {
    return switch (type) {
      ServerType.jellyfin => Icons.play_circle_filled,
      ServerType.emby => Icons.play_circle_outline,
      ServerType.audiobookshelf => Icons.headphones,
      ServerType.plex => Icons.tv,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LibrettoTheme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(_iconForType(server.type), color: LibrettoTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(server.name, style: theme.textTheme.titleMedium),
                  Text(
                    '${server.type.name.toUpperCase()}'
                    '${server.version != null ? ' v${server.version}' : ''}'
                    ' — ${server.url}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: LibrettoTheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// A card for a cloud-discovered server (Plex / Emby Connect).
class _CloudServerCard extends StatelessWidget {
  const _CloudServerCard({
    required this.server,
    required this.isConnecting,
    required this.onTap,
  });

  final CloudServer server;
  final bool isConnecting;
  final VoidCallback onTap;

  Color get _typeColor => switch (server.type) {
    ServerType.plex => LibrettoTheme.plexColor,
    ServerType.emby => LibrettoTheme.embyColor,
    ServerType.jellyfin => LibrettoTheme.jellyfinColor,
    ServerType.audiobookshelf => LibrettoTheme.audiobookshelfColor,
  };

  IconData get _typeIcon => switch (server.type) {
    ServerType.plex => Icons.tv,
    ServerType.emby => Icons.play_circle_outline,
    ServerType.jellyfin => Icons.play_circle_filled,
    ServerType.audiobookshelf => Icons.headphones,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: isConnecting ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LibrettoTheme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(_typeIcon, color: _typeColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.name,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: server.isOnline
                              ? LibrettoTheme.successColor
                              : LibrettoTheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    server.url,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: LibrettoTheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
