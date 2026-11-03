import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

// ============================================================
// CONFIGURACIÓN GENERAL Y ELEMENTOS COMPARTIDOS
// ============================================================

// Roles disponibles en el sistema.
enum UserRole {
  operator,
  supervisor,
  maintenance,
}

extension UserRoleExtension on UserRole {
  String get label {
    switch (this) {
      case UserRole.operator:
        return 'Operador';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.maintenance:
        return 'Mantenimiento';
    }
  }
}

// Modos de funcionamiento.
enum MachineMode {
  automatic,
  manual,
  stepByStep,
}

extension MachineModeExtension on MachineMode {
  String get label {
    switch (this) {
      case MachineMode.automatic:
        return 'Automático';
      case MachineMode.manual:
        return 'Manual';
      case MachineMode.stepByStep:
        return 'Paso a paso';
    }
  }
}

// Tipos de fallas que puede inyectar el Supervisor.
enum FaultType {
  highPressureB,
  lowLinePressure,
  sensorAStuck,
  timeout,
  wrongSequence,
}

extension FaultTypeExtension on FaultType {
  String get label {
    switch (this) {
      case FaultType.highPressureB:
        return 'Presión alta en pistón B';
      case FaultType.lowLinePressure:
        return 'Presión baja de línea';
      case FaultType.sensorAStuck:
        return 'Sensor A bloqueado';
      case FaultType.timeout:
        return 'Tiempo de operación excedido';
      case FaultType.wrongSequence:
        return 'Secuencia incorrecta';
    }
  }
}

enum AlarmSeverity {
  critical,
  warning,
  info,
}

extension AlarmSeverityExtension on AlarmSeverity {
  String get label {
    switch (this) {
      case AlarmSeverity.critical:
        return 'Crítica';
      case AlarmSeverity.warning:
        return 'Advertencia';
      case AlarmSeverity.info:
        return 'Información';
    }
  }
}

enum AlarmState {
  active,
  acknowledged,
  closed,
}

extension AlarmStateExtension on AlarmState {
  String get label {
    switch (this) {
      case AlarmState.active:
        return 'Activa';
      case AlarmState.acknowledged:
        return 'Reconocida';
      case AlarmState.closed:
        return 'Cerrada';
    }
  }
}

// Información de una alarma.
class AlarmRecord {
  final int id;
  final String title;
  final String description;
  final AlarmSeverity severity;
  final DateTime timestamp;

  AlarmState state;

  AlarmRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.timestamp,
    this.state = AlarmState.active,
  });
}

// Información de un ciclo terminado.
class CycleRecord {
  final int number;
  final bool success;
  final double duration;
  final double pressureA;
  final double pressureB;
  final DateTime timestamp;

  CycleRecord({
    required this.number,
    required this.success,
    required this.duration,
    required this.pressureA,
    required this.pressureB,
    required this.timestamp,
  });
}

// ============================================================
// CONTROLADOR GENERAL DE LA SIMULACIÓN
// ============================================================

class MachineController extends ChangeNotifier {
  MachineController() {
    _timer = Timer.periodic(
      const Duration(milliseconds: 150),
      _updateSimulation,
    );
  }

  late final Timer _timer;

  // Tema de la aplicación.
  final ValueNotifier<bool> darkMode = ValueNotifier(false);

  // Usuario y navegación.
  bool isLoggedIn = false;
  String username = '';
  UserRole role = UserRole.operator;
  int pageIndex = 0;

  // Estado de la máquina.
  bool enabled = false;
  bool running = false;
  bool emergencyStop = false;
  bool stopAtEnd = false;

  MachineMode mode = MachineMode.automatic;

  // Posición de los pistones: 0 = retraído, 100 = extendido.
  double positionA = 0;
  double positionB = 0;

  // Presiones simuladas.
  double pressureA = 5.8;
  double pressureB = 6.2;
  double linePressure = 6.2;

  // Límites de presión configurables por Supervisor.
  double pressureLimitA = 7.5;
  double pressureLimitB = 7.5;

  // Sensores simulados.
  bool sensorA0 = true;
  bool sensorA1 = false;
  bool sensorB0 = true;
  bool sensorB1 = false;

  // Secuencia A+ -> B+ -> A- -> B-.
  int currentStepIndex = 0;

  final List<String> sequenceSteps = [
    'A+  Extender pistón A',
    'B+  Extender pistón B',
    'A-  Retraer pistón A',
    'B-  Retraer pistón B',
  ];

  // Datos de ciclos.
  int totalCycles = 0;
  int correctCycles = 0;
  int errorCycles = 0;
  int shiftPieces = 0;

  double averageCycleTime = 0;

  final List<CycleRecord> cycleHistory = [];
  final List<AlarmRecord> alarms = [];

  int _nextAlarmId = 1;

  // Control interno de la simulación.
  double _stepElapsed = 0;
  final double _stepDuration = 1.5;

  DateTime? _cycleStart;

  bool _singleStep = false;

  // Fallas simuladas.
  bool _sensorAStuck = false;
  bool _timeoutFault = false;
  bool _wrongSequence = false;

  final Set<FaultType> activeFaults = {};

  FaultType? pendingFault;

  // ==========================================================
  // FUNCIONES GENERALES
  // ==========================================================

  bool get isSupervisor => role == UserRole.supervisor;

  bool get isMaintenance => role == UserRole.maintenance;

  String get currentStep {
    return sequenceSteps[currentStepIndex.clamp(0, 3)];
  }

  double get stepProgress {
    return (_stepElapsed / _stepDuration).clamp(0.0, 1.0);
  }

  String get machineStatus {
    if (emergencyStop) return 'PARO DE EMERGENCIA';
    if (running) return 'EN FUNCIONAMIENTO';
    if (enabled) return 'HABILITADA';
    return 'DETENIDA';
  }

  int get activeAlarmCount {
    return alarms.where((a) => a.state != AlarmState.closed).length;
  }

  int get criticalAlarmCount {
    return alarms.where(
      (a) =>
          a.severity == AlarmSeverity.critical &&
          a.state != AlarmState.closed,
    ).length;
  }

  int get warningAlarmCount {
    return alarms.where(
      (a) =>
          a.severity == AlarmSeverity.warning &&
          a.state != AlarmState.closed,
    ).length;
  }

  int get infoAlarmCount {
    return alarms.where(
      (a) =>
          a.severity == AlarmSeverity.info &&
          a.state != AlarmState.closed,
    ).length;
  }

  bool get hasUnacknowledgedAlarms {
    return alarms.any((a) => a.state == AlarmState.active);
  }

  void login(String name, UserRole selectedRole) {
    username = name;
    role = selectedRole;
    isLoggedIn = true;
    pageIndex = 0;
    notifyListeners();
  }

  void logout() {
    running = false;
    enabled = false;
    isLoggedIn = false;
    username = '';
    pageIndex = 0;
    notifyListeners();
  }

  void setPage(int index) {
    pageIndex = index;
    notifyListeners();
  }

  void toggleTheme() {
    darkMode.value = !darkMode.value;
  }

  void _updateSensors() {
    sensorA0 = !_sensorAStuck && positionA <= 5;
    sensorA1 = _sensorAStuck || positionA >= 95;

    sensorB0 = positionB <= 5;
    sensorB1 = positionB >= 95;
  }

  void _addAlarm(
    String title,
    String description,
    AlarmSeverity severity,
  ) {
    alarms.add(
      AlarmRecord(
        id: _nextAlarmId++,
        title: title,
        description: description,
        severity: severity,
        timestamp: DateTime.now(),
      ),
    );
  }

  // ==========================================================
  // CONTROL DE LA SECUENCIA
  // ==========================================================

  void setMode(MachineMode newMode) {
    if (running) return;

    mode = newMode;
    notifyListeners();
  }

  String? getEnableBlockReason() {
    if (emergencyStop) {
      return 'El paro de emergencia está activado.';
    }

    if (positionA > 5 || positionB > 5) {
      return 'Los pistones deben estar en su posición inicial.';
    }

    if (linePressure < 6.0) {
      return 'La presión de línea es insuficiente.';
    }

    if (pressureA >= pressureLimitA ||
        pressureB >= pressureLimitB) {
      return 'Existe una presión fuera del límite permitido.';
    }

    if (hasUnacknowledgedAlarms) {
      return 'Existen alarmas pendientes de reconocimiento.';
    }

    return null;
  }

  bool enableMachine() {
    if (getEnableBlockReason() != null) {
      return false;
    }

    enabled = true;
    notifyListeners();
    return true;
  }

  void disableMachine() {
    running = false;
    enabled = false;
    notifyListeners();
  }

  void startAutomatic() {
    if (mode != MachineMode.automatic) return;
    if (!enabled || emergencyStop || running) return;

    running = true;

    if (_cycleStart == null || currentStepIndex == 0) {
      _cycleStart = DateTime.now();
    }

    // Aplicar falla programada al iniciar el ciclo.
    if (pendingFault != null) {
      final fault = pendingFault!;
      pendingFault = null;
      injectFault(fault);
    }

    notifyListeners();
  }

  void runOneStep() {
    if (mode != MachineMode.stepByStep) return;
    if (!enabled || emergencyStop || running) return;

    running = true;
    _singleStep = true;

    if (_cycleStart == null || currentStepIndex == 0) {
      _cycleStart = DateTime.now();
    }

    notifyListeners();
  }

  void stopMachine() {
    running = false;
    _singleStep = false;
    notifyListeners();
  }

  void setStopAtEnd(bool value) {
    stopAtEnd = value;
    notifyListeners();
  }

  void resetSequence() {
    if (running || emergencyStop) return;

    currentStepIndex = 0;
    _stepElapsed = 0;

    positionA = 0;
    positionB = 0;

    _updateSensors();

    notifyListeners();
  }

  void manualMoveA(bool extend) {
    if (mode != MachineMode.manual ||
        !enabled ||
        running ||
        emergencyStop) {
      return;
    }

    positionA = extend ? 100 : 0;
    _updateSensors();
    notifyListeners();
  }

  void manualMoveB(bool extend) {
    if (mode != MachineMode.manual ||
        !enabled ||
        running ||
        emergencyStop) {
      return;
    }

    positionB = extend ? 100 : 0;
    _updateSensors();
    notifyListeners();
  }

  // ==========================================================
  // MOTOR DE SIMULACIÓN
  // ==========================================================

  void _updateSimulation(Timer timer) {
    if (!running) return;

    _stepElapsed += 0.15;

    // Simulación de tiempo excedido.
    if (_timeoutFault && _stepElapsed >= _stepDuration * 2) {
      _timeoutFault = false;

      running = false;
      enabled = false;

      errorCycles++;

      _addAlarm(
        'Tiempo de operación excedido',
        'El pistón no completó su movimiento dentro del tiempo establecido.',
        AlarmSeverity.critical,
      );

      notifyListeners();
      return;
    }

    final progress = (_stepElapsed / _stepDuration).clamp(0.0, 1.0);

    switch (currentStepIndex) {
      case 0:
        // A+
        positionA = progress * 100;
        positionB = 0;
        break;

      case 1:
        // B+
        positionA = 100;
        positionB = progress * 100;
        break;

      case 2:
        // A-
        positionA = (1 - progress) * 100;
        positionB = 100;
        break;

      case 3:
        // B-
        positionA = 0;
        positionB = (1 - progress) * 100;
        break;
    }

    _updateSensors();

    if (_stepElapsed >= _stepDuration) {
      _finishStep();
    }

    notifyListeners();
  }

  void _finishStep() {
    _stepElapsed = 0;

    // Falla de secuencia: se omite un movimiento.
    if (_wrongSequence) {
      currentStepIndex = (currentStepIndex + 2) % 4;
      _wrongSequence = false;
    } else {
      currentStepIndex++;
    }

    if (currentStepIndex >= 4) {
      _completeCycle();
      return;
    }

    // En modo paso a paso, se detiene después de cada movimiento.
    if (_singleStep) {
      running = false;
      _singleStep = false;
    }
  }

  void _completeCycle() {
    final duration = _cycleStart == null
        ? 0.0
        : DateTime.now()
            .difference(_cycleStart!)
            .inMilliseconds /
            1000;

    final hasError = activeFaults.any(
      (fault) => fault != FaultType.highPressureB,
    );

    totalCycles++;

    if (hasError) {
      errorCycles++;
    } else {
      correctCycles++;
    }

    shiftPieces = totalCycles;

    cycleHistory.add(
      CycleRecord(
        number: totalCycles,
        success: !hasError,
        duration: duration,
        pressureA: pressureA,
        pressureB: pressureB,
        timestamp: DateTime.now(),
      ),
    );

    if (cycleHistory.length > 100) {
      cycleHistory.removeAt(0);
    }

    averageCycleTime = cycleHistory.fold<double>(
          0,
          (sum, item) => sum + item.duration,
        ) /
        cycleHistory.length;

    final wasSingleStep = _singleStep;

    currentStepIndex = 0;
    _stepElapsed = 0;

    positionA = 0;
    positionB = 0;

    _updateSensors();

    _cycleStart = DateTime.now();

    if (stopAtEnd || wasSingleStep || mode != MachineMode.automatic) {
      running = false;
      _singleStep = false;
    }
  }

  // ==========================================================
  // PARO DE EMERGENCIA
  // ==========================================================

  void emergencyStopNow() {
    if (emergencyStop) return;

    emergencyStop = true;
    running = false;
    enabled = false;

    _addAlarm(
      'Paro de emergencia activado',
      'La máquina fue detenida mediante el paro de emergencia.',
      AlarmSeverity.critical,
    );

    notifyListeners();
  }

  void resetEmergencyStop() {
    if (!isMaintenance) return;

    emergencyStop = false;
    enabled = false;

    _addAlarm(
      'Paro de emergencia restablecido',
      'El sistema de emergencia fue restablecido por Mantenimiento.',
      AlarmSeverity.info,
    );

    notifyListeners();
  }

  // ==========================================================
  // CONTROL DE ALARMAS
  // ==========================================================

  void acknowledgeAlarm(int id) {
    if (!isMaintenance) return;

    final alarm = alarms.firstWhere(
      (a) => a.id == id,
    );

    if (alarm.state == AlarmState.active) {
      alarm.state = AlarmState.acknowledged;
    }

    notifyListeners();
  }

  void closeAlarm(int id) {
    if (!isMaintenance) return;

    final alarm = alarms.firstWhere(
      (a) => a.id == id,
    );

    if (alarm.state == AlarmState.acknowledged) {
      alarm.state = AlarmState.closed;
    }

    notifyListeners();
  }

  // ==========================================================
  // FUNCIONES DEL SUPERVISOR / INSTRUCTOR
  // ==========================================================

  void setPressureLimitA(double value) {
    if (!isSupervisor) return;

    pressureLimitA = value;
    notifyListeners();
  }

  void setPressureLimitB(double value) {
    if (!isSupervisor) return;

    pressureLimitB = value;
    notifyListeners();
  }

  void scheduleFault(FaultType fault) {
    if (!isSupervisor) return;

    pendingFault = fault;
    notifyListeners();
  }

  void injectFault(FaultType fault) {
    if (!isSupervisor) return;

    activeFaults.add(fault);

    switch (fault) {
      case FaultType.highPressureB:
        pressureB = 7.9;

        _addAlarm(
          'Presión alta en pistón B',
          'Presión actual: 7.9 bar. Límite permitido: $pressureLimitB bar. No detiene la máquina.',
          AlarmSeverity.warning,
        );
        break;

      case FaultType.lowLinePressure:
        linePressure = 4.5;

        _addAlarm(
          'Presión baja de línea',
          'La presión de alimentación disminuyó a 4.5 bar.',
          AlarmSeverity.critical,
        );

        if (running) {
          running = false;
          enabled = false;
        }
        break;

      case FaultType.sensorAStuck:
        _sensorAStuck = true;

        _addAlarm(
          'Sensor A bloqueado',
          'El sensor del pistón A permanece activado independientemente de su posición.',
          AlarmSeverity.critical,
        );
        break;

      case FaultType.timeout:
        _timeoutFault = true;
        break;

      case FaultType.wrongSequence:
        _wrongSequence = true;

        _addAlarm(
          'Secuencia incorrecta',
          'Se detectó una alteración en el orden de los movimientos.',
          AlarmSeverity.critical,
        );
        break;
    }

    _updateSensors();
    notifyListeners();
  }

  void repairSimulation() {
    if (!isSupervisor) return;

    pressureA = 5.8;
    pressureB = 6.2;
    linePressure = 6.2;

    _sensorAStuck = false;
    _timeoutFault = false;
    _wrongSequence = false;

    activeFaults.clear();
    pendingFault = null;

    enabled = false;
    running = false;

    _updateSensors();

    _addAlarm(
      'Simulación restablecida',
      'Las condiciones simuladas de la máquina fueron restauradas.',
      AlarmSeverity.info,
    );

    notifyListeners();
  }

  @override
  void dispose() {
    _timer.cancel();
    darkMode.dispose();
    super.dispose();
  }
}

// ============================================================
// APLICACIÓN PRINCIPAL
// ============================================================

void main() {
  runApp(const PistonSimulatorApp());
}

class PistonSimulatorApp extends StatefulWidget {
  const PistonSimulatorApp({super.key});

  @override
  State<PistonSimulatorApp> createState() =>
      _PistonSimulatorAppState();
}

class _PistonSimulatorAppState extends State<PistonSimulatorApp> {
  late final MachineController controller;

  @override
  void initState() {
    super.initState();
    controller = MachineController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.darkMode,
      builder: (context, isDark, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Secuencia de Pistones',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF245B91),
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF5B9BD5),
              brightness: Brightness.dark,
            ),
          ),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          home: AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              if (!controller.isLoggedIn) {
                return LoginInterface(
                  controller: controller,
                );
              }

              return HomeShell(
                controller: controller,
              );
            },
          ),
        );
      },
    );
  }
}

// ============================================================
// INTERFAZ 1: INICIO DE SESIÓN
// ============================================================

class LoginInterface extends StatefulWidget {
  final MachineController controller;

  const LoginInterface({
    super.key,
    required this.controller,
  });

  @override
  State<LoginInterface> createState() =>
      _LoginInterfaceState();
}

class _LoginInterfaceState extends State<LoginInterface> {
  final TextEditingController userController =
      TextEditingController();

  final TextEditingController passwordController =
      TextEditingController();

  UserRole selectedRole = UserRole.operator;

  bool hidePassword = true;

  @override
  void dispose() {
    userController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void login() {
    if (userController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa el usuario y la contraseña.'),
        ),
      );
      return;
    }

    widget.controller.login(
      userController.text.trim(),
      selectedRole,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 430,
            ),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.precision_manufacturing,
                      size: 65,
                      color: Color(0xFF3979B8),
                    ),

                    const SizedBox(height: 18),

                    const Text(
                      'SECUENCIA DE PISTONES',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Sistema de supervisión y simulación',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 30),

                    TextField(
                      controller: userController,
                      decoration: const InputDecoration(
                        labelText: 'Usuario',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: passwordController,
                      obscureText: hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              hidePassword = !hidePassword;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    DropdownButtonFormField<UserRole>(
                      value: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de usuario',
                        prefixIcon: Icon(Icons.badge),
                        border: OutlineInputBorder(),
                      ),
                      items: UserRole.values.map((role) {
                        return DropdownMenuItem(
                          value: role,
                          child: Text(role.label),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedRole = value;
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 22),

                    FilledButton.icon(
                      onPressed: login,
                      icon: const Icon(Icons.login),
                      label: const Text('Iniciar sesión'),
                    ),

                    const SizedBox(height: 14),

                    OutlinedButton.icon(
                      onPressed: widget.controller.emergencyStopNow,
                      icon: const Icon(
                        Icons.warning,
                        color: Colors.red,
                      ),
                      label: const Text(
                        'PARO DE EMERGENCIA',
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Simulación local: las credenciales son de demostración y no existe conexión con equipos externos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// NAVEGACIÓN GENERAL DE LAS INTERFACES
// ============================================================

class HomeShell extends StatelessWidget {
  final MachineController controller;

  const HomeShell({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardInterface(controller: controller),
      ProcessInterface(controller: controller),
      StopEnableInterface(controller: controller),
      AlertsInterface(controller: controller),
      RecordsInterface(controller: controller),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Secuencia de Pistones',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
              ),
              child: Chip(
                avatar: const Icon(Icons.person, size: 17),
                label: Text(controller.role.label),
              ),
            ),
          ),

          IconButton(
            tooltip: 'Paro de emergencia',
            icon: const Icon(
              Icons.emergency,
              color: Colors.red,
            ),
            onPressed: controller.emergencyStopNow,
          ),

          IconButton(
            tooltip: 'Cambiar tema',
            icon: Icon(
              controller.darkMode.value
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: controller.toggleTheme,
          ),

          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: controller.logout,
          ),

          const SizedBox(width: 8),
        ],
      ),

      body: IndexedStack(
        index: controller.pageIndex,
        children: pages,
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: controller.pageIndex,
        onDestinationSelected: controller.setPage,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Estado',
          ),
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: Icon(Icons.precision_manufacturing),
            label: 'Proceso',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune),
            selectedIcon: Icon(Icons.settings),
            label: 'Control',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alertas',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Registro',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// COMPONENTES COMPARTIDOS DE LAS INTERFACES
// ============================================================

class PageHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const PageHeading({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String description;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.description,
    required this.icon,
    this.color = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Text(
              value,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class PistonCard extends StatelessWidget {
  final String name;
  final double pressure;
  final double position;
  final double limit;
  final bool sensorRetracted;
  final bool sensorExtended;

  const PistonCard({
    super.key,
    required this.name,
    required this.pressure,
    required this.position,
    required this.limit,
    required this.sensorRetracted,
    required this.sensorExtended,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = pressure >= limit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings),
                const SizedBox(width: 8),
                Text(
                  'Pistón $name',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Icon(
                  isHigh ? Icons.warning : Icons.check_circle,
                  color: isHigh ? Colors.red : Colors.green,
                ),
              ],
            ),

            const SizedBox(height: 20),

            Text(
              'Presión: ${pressure.toStringAsFixed(1)} bar',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 7),

            LinearProgressIndicator(
              value: (pressure / 10).clamp(0.0, 1.0),
              minHeight: 9,
              color: isHigh ? Colors.red : Colors.blue,
            ),

            const SizedBox(height: 8),

            Text('Límite: ${limit.toStringAsFixed(1)} bar'),

            const SizedBox(height: 18),

            Text(
              'Carrera: ${position.toStringAsFixed(0)} mm',
            ),

            const SizedBox(height: 7),

            LinearProgressIndicator(
              value: (position / 100).clamp(0.0, 1.0),
              minHeight: 9,
            ),

            const SizedBox(height: 16),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SensorBadge(
                  label: '${name}0',
                  active: sensorRetracted,
                ),
                SensorBadge(
                  label: '${name}1',
                  active: sensorExtended,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SensorBadge extends StatelessWidget {
  final String label;
  final bool active;

  const SensorBadge({
    super.key,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        active ? Icons.check_circle : Icons.circle_outlined,
        size: 17,
        color: active ? Colors.green : Colors.grey,
      ),
      label: Text('$label ${active ? "ON" : "OFF"}'),
    );
  }
}

class SequenceStepTile extends StatelessWidget {
  final String title;
  final int number;
  final bool active;
  final bool completed;

  const SequenceStepTile({
    super.key,
    required this.title,
    required this.number,
    required this.active,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? Colors.green
        : active
            ? Colors.blue
            : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Card(
      color: active
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color,
              child: Text(
                '$number',
                style: TextStyle(
                  color: active || completed
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (completed)
              const Icon(Icons.check_circle, color: Colors.green),
            if (active)
              const Icon(Icons.play_circle, color: Colors.blue),
          ],
        ),
      ),
    );
  }
}

class SensorCard extends StatelessWidget {
  final String name;
  final bool active;

  const SensorCard({
    super.key,
    required this.name,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              active ? Icons.sensors : Icons.sensors_off,
              color: active ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              active ? 'ACTIVO' : 'INACTIVO',
              style: TextStyle(
                color: active ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// INTERFAZ 2: DIAGRAMA Y ESTADO DE LA MÁQUINA
// ============================================================

class DashboardInterface extends StatelessWidget {
  final MachineController controller;

  const DashboardInterface({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final steps = controller.sequenceSteps;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Diagrama y estado de la máquina',
            subtitle: 'Supervisión general del sistema de pistones.',
          ),

          const SizedBox(height: 20),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 220,
                child: MetricCard(
                  title: 'Estado',
                  value: controller.machineStatus,
                  description: 'Condición actual',
                  icon: Icons.monitor_heart,
                  color: controller.running
                      ? Colors.green
                      : Colors.orange,
                ),
              ),

              SizedBox(
                width: 220,
                child: MetricCard(
                  title: 'Ciclo actual',
                  value: '${controller.totalCycles + 1}',
                  description: 'Número de ciclo',
                  icon: Icons.repeat,
                ),
              ),

              SizedBox(
                width: 220,
                child: MetricCard(
                  title: 'Piezas del turno',
                  value: '${controller.shiftPieces}',
                  description: 'Producción acumulada',
                  icon: Icons.inventory,
                ),
              ),

              SizedBox(
                width: 220,
                child: MetricCard(
                  title: 'Alarmas activas',
                  value: '${controller.activeAlarmCount}',
                  description: 'Alarmas sin cerrar',
                  icon: Icons.warning_amber,
                  color: Colors.orange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          const Text(
            'Estado de los pistones',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth > 750
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: width,
                    child: PistonCard(
                      name: 'A',
                      pressure: controller.pressureA,
                      position: controller.positionA,
                      limit: controller.pressureLimitA,
                      sensorRetracted: controller.sensorA0,
                      sensorExtended: controller.sensorA1,
                    ),
                  ),

                  SizedBox(
                    width: width,
                    child: PistonCard(
                      name: 'B',
                      pressure: controller.pressureB,
                      position: controller.positionB,
                      limit: controller.pressureLimitB,
                      sensorRetracted: controller.sensorB0,
                      sensorExtended: controller.sensorB1,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 22),

          const Text(
            'Secuencia de operación',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          ...List.generate(4, (index) {
            return SequenceStepTile(
              number: index + 1,
              title: steps[index],
              active: controller.running &&
                  controller.currentStepIndex == index,
              completed: controller.running
                  ? index < controller.currentStepIndex
                  : false,
            );
          }),

          const SizedBox(height: 18),

          Card(
            child: ListTile(
              leading: const Icon(Icons.compress),
              title: const Text('Presión de línea'),
              subtitle: Text(
                '${controller.linePressure.toStringAsFixed(1)} bar',
              ),
              trailing: Text(
                controller.linePressure >= 6
                    ? 'Normal'
                    : 'Baja',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: controller.linePressure >= 6
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INTERFAZ 3: PROCESO ACTUAL
// ============================================================

class ProcessInterface extends StatelessWidget {
  final MachineController controller;

  const ProcessInterface({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Proceso actual',
            subtitle: 'Seguimiento del movimiento y avance de la secuencia.',
          ),

          const SizedBox(height: 22),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paso ${controller.currentStepIndex + 1} de 4',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    controller.currentStep,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 18),

                  LinearProgressIndicator(
                    value: controller.running
                        ? controller.stepProgress
                        : 0,
                    minHeight: 12,
                  ),

                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Avance: ${(controller.stepProgress * 100).toStringAsFixed(0)}%',
                      ),
                      Text(
                        'Tiempo: ${controller.running ? (controller.stepProgress * 1.5).toStringAsFixed(1) : "0.0"} / 1.5 s',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'Posición de los pistones',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          PistonCard(
            name: 'A',
            pressure: controller.pressureA,
            position: controller.positionA,
            limit: controller.pressureLimitA,
            sensorRetracted: controller.sensorA0,
            sensorExtended: controller.sensorA1,
          ),

          const SizedBox(height: 12),

          PistonCard(
            name: 'B',
            pressure: controller.pressureB,
            position: controller.positionB,
            limit: controller.pressureLimitB,
            sensorRetracted: controller.sensorB0,
            sensorExtended: controller.sensorB1,
          ),

          const SizedBox(height: 20),

          const Text(
            'Estado de sensores',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.8,
            children: [
              SensorCard(
                name: 'Sensor A0',
                active: controller.sensorA0,
              ),
              SensorCard(
                name: 'Sensor A1',
                active: controller.sensorA1,
              ),
              SensorCard(
                name: 'Sensor B0',
                active: controller.sensorB0,
              ),
              SensorCard(
                name: 'Sensor B1',
                active: controller.sensorB1,
              ),
            ],
          ),

          const SizedBox(height: 20),

          const Text(
            'Orden de movimientos',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: const Text('1. A+'),
                backgroundColor:
                    controller.currentStepIndex == 0
                        ? Colors.blue.withOpacity(0.2)
                        : null,
              ),
              Chip(
                label: const Text('2. B+'),
                backgroundColor:
                    controller.currentStepIndex == 1
                        ? Colors.blue.withOpacity(0.2)
                        : null,
              ),
              Chip(
                label: const Text('3. A-'),
                backgroundColor:
                    controller.currentStepIndex == 2
                        ? Colors.blue.withOpacity(0.2)
                        : null,
              ),
              Chip(
                label: const Text('4. B-'),
                backgroundColor:
                    controller.currentStepIndex == 3
                        ? Colors.blue.withOpacity(0.2)
                        : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INTERFAZ 4: PARO Y HABILITACIÓN
// ============================================================

class StopEnableInterface extends StatelessWidget {
  final MachineController controller;

  const StopEnableInterface({
    super.key,
    required this.controller,
  });

  void showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blockReason = controller.getEnableBlockReason();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Paro y habilitación',
            subtitle: 'Control de operación y condiciones de seguridad.',
          ),

          const SizedBox(height: 20),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Control de la máquina',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 18),

                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: controller.running
                            ? null
                            : () {
                                if (controller.mode ==
                                    MachineMode.automatic) {
                                  controller.startAutomatic();
                                } else if (controller.mode ==
                                    MachineMode.stepByStep) {
                                  controller.runOneStep();
                                } else {
                                  showMessage(
                                    context,
                                    'Selecciona los movimientos manuales.',
                                  );
                                }
                              },
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          controller.mode == MachineMode.stepByStep
                              ? 'Ejecutar paso'
                              : 'Iniciar',
                        ),
                      ),

                      OutlinedButton.icon(
                        onPressed: controller.stopMachine,
                        icon: const Icon(Icons.stop),
                        label: const Text('Detener'),
                      ),

                      OutlinedButton.icon(
                        onPressed: controller.resetSequence,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reiniciar secuencia'),
                      ),

                      if (controller.isMaintenance)
                        FilledButton.tonalIcon(
                          onPressed: controller.emergencyStop
                              ? controller.resetEmergencyStop
                              : null,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Restablecer emergencia'),
                        ),
                    ],
                  ),

                  const Divider(height: 30),

                  FilledButton.icon(
                    onPressed: controller.enabled
                        ? controller.disableMachine
                        : () {
                            final reason =
                                controller.getEnableBlockReason();

                            if (reason == null) {
                              controller.enableMachine();
                              showMessage(
                                context,
                                'Máquina habilitada.',
                              );
                            } else {
                              showMessage(context, reason);
                            }
                          },
                    icon: Icon(
                      controller.enabled
                          ? Icons.power_off
                          : Icons.power,
                    ),
                    label: Text(
                      controller.enabled
                          ? 'Deshabilitar máquina'
                          : 'Habilitar máquina',
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    blockReason == null
                        ? 'Condiciones de habilitación correctas.'
                        : 'No se puede habilitar: $blockReason',
                    style: TextStyle(
                      color: blockReason == null
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          Card(
            child: SwitchListTile(
              title: const Text('Paro al finalizar el ciclo'),
              subtitle: const Text(
                'Detiene la máquina cuando termina la secuencia actual.',
              ),
              value: controller.stopAtEnd,
              onChanged: controller.setStopAtEnd,
            ),
          ),

          const SizedBox(height: 18),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modo de operación',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 15),

                  SegmentedButton<MachineMode>(
                    segments: const [
                      ButtonSegment(
                        value: MachineMode.automatic,
                        label: Text('Automático'),
                        icon: Icon(Icons.autorenew),
                      ),
                      ButtonSegment(
                        value: MachineMode.manual,
                        label: Text('Manual'),
                        icon: Icon(Icons.pan_tool),
                      ),
                      ButtonSegment(
                        value: MachineMode.stepByStep,
                        label: Text('Paso a paso'),
                        icon: Icon(Icons.skip_next),
                      ),
                    ],
                    selected: {controller.mode},
                    onSelectionChanged: (value) {
                      controller.setMode(value.first);
                    },
                  ),
                ],
              ),
            ),
          ),

          if (controller.mode == MachineMode.manual) ...[
            const SizedBox(height: 18),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Movimientos manuales',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 14),

                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              controller.manualMoveA(true),
                          child: const Text('A+ Extender'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              controller.manualMoveA(false),
                          child: const Text('A- Retraer'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              controller.manualMoveB(true),
                          child: const Text('B+ Extender'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              controller.manualMoveB(false),
                          child: const Text('B- Retraer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Edición de límites exclusiva del Supervisor.
          if (controller.isSupervisor)
            PressureLimitEditor(controller: controller),

          const SizedBox(height: 18),

          // Herramientas de instructor exclusivas del Supervisor.
          if (controller.isSupervisor)
            FaultInstructorPanel(controller: controller),

          const SizedBox(height: 18),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumen del turno',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text('Ciclos realizados: ${controller.totalCycles}'),
                  Text('Ciclos correctos: ${controller.correctCycles}'),
                  Text('Ciclos con error: ${controller.errorCycles}'),
                  Text(
                    'Tiempo promedio: ${controller.averageCycleTime.toStringAsFixed(2)} s',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EDICIÓN DE PRESIONES DEL SUPERVISOR
// ============================================================

class PressureLimitEditor extends StatelessWidget {
  final MachineController controller;

  const PressureLimitEditor({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Límites de presión',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Pistón A: ${controller.pressureLimitA.toStringAsFixed(1)} bar',
            ),

            Slider(
              value: controller.pressureLimitA,
              min: 5,
              max: 10,
              divisions: 10,
              label:
                  '${controller.pressureLimitA.toStringAsFixed(1)} bar',
              onChanged: controller.setPressureLimitA,
            ),

            const SizedBox(height: 10),

            Text(
              'Pistón B: ${controller.pressureLimitB.toStringAsFixed(1)} bar',
            ),

            Slider(
              value: controller.pressureLimitB,
              min: 5,
              max: 10,
              divisions: 10,
              label:
                  '${controller.pressureLimitB.toStringAsFixed(1)} bar',
              onChanged: controller.setPressureLimitB,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HERRAMIENTAS DE INSTRUCTOR DEL SUPERVISOR
// ============================================================

class FaultInstructorPanel extends StatefulWidget {
  final MachineController controller;

  const FaultInstructorPanel({
    super.key,
    required this.controller,
  });

  @override
  State<FaultInstructorPanel> createState() =>
      _FaultInstructorPanelState();
}

class _FaultInstructorPanelState extends State<FaultInstructorPanel> {
  FaultType selectedFault = FaultType.highPressureB;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.school),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Herramientas de instructor',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            const Text(
              'Permite introducir fallas para comprobar las respuestas de la simulación.',
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<FaultType>(
              value: selectedFault,
              decoration: const InputDecoration(
                labelText: 'Falla a simular',
                border: OutlineInputBorder(),
              ),
              items: FaultType.values.map((fault) {
                return DropdownMenuItem(
                  value: fault,
                  child: Text(fault.label),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    selectedFault = value;
                  });
                }
              },
            ),

            const SizedBox(height: 14),

            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    controller.injectFault(selectedFault);
                  },
                  icon: const Icon(Icons.warning),
                  label: const Text('Inyectar falla'),
                ),

                OutlinedButton.icon(
                  onPressed: () {
                    controller.scheduleFault(selectedFault);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Falla programada para el siguiente ciclo.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.schedule),
                  label: const Text('Programar falla'),
                ),

                OutlinedButton.icon(
                  onPressed: controller.repairSimulation,
                  icon: const Icon(Icons.build_circle),
                  label: const Text('Restablecer simulación'),
                ),
              ],
            ),

            const Divider(height: 28),

            const Text(
              'Fallas activas:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            if (controller.activeFaults.isEmpty)
              const Text('No hay fallas simuladas activas.')
            else
              ...controller.activeFaults.map(
                (fault) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('• ${fault.label}'),
                ),
              ),

            if (controller.pendingFault != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Próxima falla programada: ${controller.pendingFault!.label}',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// INTERFAZ 5: ALERTAS Y REGISTROS
// ============================================================

class AlertsInterface extends StatelessWidget {
  final MachineController controller;

  const AlertsInterface({
    super.key,
    required this.controller,
  });

  Color severityColor(AlarmSeverity severity) {
    switch (severity) {
      case AlarmSeverity.critical:
        return Colors.red;
      case AlarmSeverity.warning:
        return Colors.orange;
      case AlarmSeverity.info:
        return Colors.blue;
    }
  }

  String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final reversedAlarms = controller.alarms.reversed.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Alertas y registros',
            subtitle: 'Historial y seguimiento de eventos del sistema.',
          ),

          const SizedBox(height: 20),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 160,
                child: MetricCard(
                  title: 'Total activas',
                  value: '${controller.activeAlarmCount}',
                  description: 'Sin cerrar',
                  icon: Icons.notifications,
                ),
              ),

              SizedBox(
                width: 160,
                child: MetricCard(
                  title: 'Críticas',
                  value: '${controller.criticalAlarmCount}',
                  description: 'Prioridad alta',
                  icon: Icons.error,
                  color: Colors.red,
                ),
              ),

              SizedBox(
                width: 160,
                child: MetricCard(
                  title: 'Advertencias',
                  value: '${controller.warningAlarmCount}',
                  description: 'Requieren revisión',
                  icon: Icons.warning,
                  color: Colors.orange,
                ),
              ),

              SizedBox(
                width: 160,
                child: MetricCard(
                  title: 'Información',
                  value: '${controller.infoAlarmCount}',
                  description: 'Eventos registrados',
                  icon: Icons.info,
                  color: Colors.blue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Historial de alarmas',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              if (controller.isMaintenance)
                const Chip(
                  label: Text('Mantenimiento'),
                  avatar: Icon(Icons.build, size: 17),
                ),
            ],
          ),

          const SizedBox(height: 12),

          if (reversedAlarms.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 45,
                        color: Colors.green,
                      ),
                      SizedBox(height: 10),
                      Text('No existen alarmas registradas.'),
                    ],
                  ),
                ),
              ),
            ),

          ...reversedAlarms.map((alarm) {
            final color = severityColor(alarm.severity);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: color,
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Text(
                            alarm.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),

                        Chip(
                          label: Text(alarm.severity.label),
                          backgroundColor: color.withOpacity(0.15),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Text(alarm.description),

                    const SizedBox(height: 8),

                    Text(
                      'Fecha: ${formatDate(alarm.timestamp)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Text('Estado: '),

                        Text(
                          alarm.state.label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: alarm.state == AlarmState.closed
                                ? Colors.green
                                : alarm.state == AlarmState.active
                                    ? Colors.orange
                                    : Colors.blue,
                          ),
                        ),

                        const Spacer(),

                        if (controller.isMaintenance &&
                            alarm.state == AlarmState.active)
                          TextButton(
                            onPressed: () {
                              controller.acknowledgeAlarm(alarm.id);
                            },
                            child: const Text('Reconocer'),
                          ),

                        if (controller.isMaintenance &&
                            alarm.state == AlarmState.acknowledged)
                          TextButton(
                            onPressed: () {
                              controller.closeAlarm(alarm.id);
                            },
                            child: const Text('Cerrar'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 10),

          const Text(
            'Permisos: solamente Mantenimiento puede reconocer y cerrar alarmas.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INTERFAZ 6: REGISTRO DE SECUENCIA
// ============================================================

enum RecordRange {
  today,
  week,
  month,
}

class RecordsInterface extends StatefulWidget {
  final MachineController controller;

  const RecordsInterface({
    super.key,
    required this.controller,
  });

  @override
  State<RecordsInterface> createState() =>
      _RecordsInterfaceState();
}

class _RecordsInterfaceState extends State<RecordsInterface> {
  RecordRange selectedRange = RecordRange.today;

  List<CycleRecord> get filteredRecords {
    final now = DateTime.now();

    return widget.controller.cycleHistory.where((record) {
      final difference = now.difference(record.timestamp).inDays;

      switch (selectedRange) {
        case RecordRange.today:
          return record.timestamp.year == now.year &&
              record.timestamp.month == now.month &&
              record.timestamp.day == now.day;

        case RecordRange.week:
          return difference <= 7;

        case RecordRange.month:
          return difference <= 30;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final records = filteredRecords;

    final correct = records.where((r) => r.success).length;
    final errors = records.length - correct;

    final average = records.isEmpty
        ? 0.0
        : records.fold<double>(
              0,
              (sum, item) => sum + item.duration,
            ) /
            records.length;

    final maxPressureA = records.isEmpty
        ? 0.0
        : records
            .map((e) => e.pressureA)
            .reduce((a, b) => a > b ? a : b);

    final maxPressureB = records.isEmpty
        ? 0.0
        : records
            .map((e) => e.pressureB)
            .reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Registro de secuencia',
            subtitle: 'Estadísticas e historial de ciclos de producción.',
          ),

          const SizedBox(height: 20),

          SegmentedButton<RecordRange>(
            segments: const [
              ButtonSegment(
                value: RecordRange.today,
                label: Text('Hoy'),
              ),
              ButtonSegment(
                value: RecordRange.week,
                label: Text('Semana'),
              ),
              ButtonSegment(
                value: RecordRange.month,
                label: Text('Mes'),
              ),
            ],
            selected: {selectedRange},
            onSelectionChanged: (value) {
              setState(() {
                selectedRange = value.first;
              });
            },
          ),

          const SizedBox(height: 20),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 160,
                child: MetricCard(
                  title: 'Ciclos',
                  value: '${records.length}',
                  description: 'Ciclos registrados',
                  icon: Icons.repeat,
                ),
              ),

              SizedBox(
                width: 160,
                child: MetricCard(
                  title: 'Correctos',
                  value: '$correct',
                  description: 'Sin errores',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
              ),

              SizedBox(
                width: 160,
                child: MetricCard(
                  title: 'Errores',
                  value: '$errors',
                  description: 'Ciclos con error',
                  icon: Icons.error,
                  color: Colors.red,
                ),
              ),

              SizedBox(
                width: 160,
                child: MetricCard(
                  title: 'Tiempo promedio',
                  value: '${average.toStringAsFixed(2)} s',
                  description: 'Por ciclo',
                  icon: Icons.timer,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Últimos ciclos',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 15),

                  SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: records.isEmpty
                        ? const Center(
                            child: Text(
                              'No existen ciclos registrados en este periodo.',
                            ),
                          )
                        : CustomPaint(
                            painter: CycleChartPainter(records),
                            child: const SizedBox.expand(),
                          ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Presiones máximas registradas',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Pistón A: ${maxPressureA.toStringAsFixed(1)} bar',
                  ),

                  Text(
                    'Pistón B: ${maxPressureB.toStringAsFixed(1)} bar',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'Detalle de ciclos',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          if (records.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'El historial aparecerá aquí cuando se completen ciclos.',
                ),
              ),
            )
          else
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Ciclo')),
                    DataColumn(label: Text('Estado')),
                    DataColumn(label: Text('Tiempo')),
                    DataColumn(label: Text('Presión A')),
                    DataColumn(label: Text('Presión B')),
                  ],
                  rows: records.reversed.map((record) {
                    return DataRow(
                      cells: [
                        DataCell(Text('${record.number}')),
                        DataCell(
                          Text(
                            record.success ? 'Correcto' : 'Error',
                            style: TextStyle(
                              color: record.success
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${record.duration.toStringAsFixed(2)} s',
                          ),
                        ),
                        DataCell(
                          Text(
                            '${record.pressureA.toStringAsFixed(1)} bar',
                          ),
                        ),
                        DataCell(
                          Text(
                            '${record.pressureB.toStringAsFixed(1)} bar',
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// GRÁFICA DE HISTORIAL DE CICLOS
// ============================================================

class CycleChartPainter extends CustomPainter {
  final List<CycleRecord> records;

  CycleChartPainter(this.records);

  @override
  void paint(Canvas canvas, Size size) {
    if (records.isEmpty) return;

    final visibleRecords = records.length > 30
        ? records.sublist(records.length - 30)
        : records;

    final maxDuration = visibleRecords
        .map((record) => record.duration)
        .reduce((a, b) => a > b ? a : b);

    final maxValue = maxDuration <= 0 ? 1.0 : maxDuration;

    final spacing = size.width / visibleRecords.length;
    final barWidth = spacing * 0.65;

    final basePaint = Paint()
      ..color = Colors.grey.withOpacity(0.4)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, size.height - 5),
      Offset(size.width, size.height - 5),
      basePaint,
    );

    for (int i = 0; i < visibleRecords.length; i++) {
      final record = visibleRecords[i];

      final barHeight =
          (record.duration / maxValue) * (size.height - 25);

      final x = i * spacing + (spacing - barWidth) / 2;

      final paint = Paint()
        ..color = record.success ? Colors.green : Colors.red;

      final rect = Rect.fromLTWH(
        x,
        size.height - barHeight - 5,
        barWidth,
        barHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CycleChartPainter oldDelegate) {
    return oldDelegate.records != records;
  }
}