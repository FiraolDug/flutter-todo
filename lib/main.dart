import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(const TodoApp());
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart ToDo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: const TodoHomePage(),
    );
  }
}

class TodoHomePage extends StatefulWidget {
  const TodoHomePage({super.key});

  @override
  State<TodoHomePage> createState() => _TodoHomePageState();
}

class _TodoHomePageState extends State<TodoHomePage>
    with TickerProviderStateMixin {
  final _taskController = TextEditingController();
  final _searchController = TextEditingController();
  List<Task> _tasks = [];
  List<Task> _filteredTasks = [];
  SharedPreferences? _prefs;
  Task? _recentlyDeletedTask;
  int? _recentlyDeletedTaskIndex;
  
  // Filter states
  TaskFilter _currentFilter = TaskFilter.all;
  String _searchQuery = '';
  
  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  
  // Task statistics
  int get _totalTasks => _tasks.length;
  int get _completedTasks => _tasks.where((t) => t.done).length;
  int get _activeTasks => _totalTasks - _completedTasks;
  double get _completionRate => _totalTasks > 0 ? _completedTasks / _totalTasks : 0.0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _loadTasks();
  }

  @override
  void dispose() {
    _taskController.dispose();
    _searchController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    _prefs = await SharedPreferences.getInstance();
    final String? tasksString = _prefs?.getString('tasks');
    if (tasksString != null) {
      final List decoded = jsonDecode(tasksString);
      setState(() {
        _tasks = decoded.map((e) => Task.fromJson(e)).toList();
        _applyFilters();
      });
    }
  }

  Future<void> _saveTasks() async {
    final String encoded = jsonEncode(_tasks.map((e) => e.toJson()).toList());
    await _prefs?.setString('tasks', encoded);
  }

  void _applyFilters() {
    setState(() {
      _filteredTasks = _tasks.where((task) {
        // Apply search filter
        if (_searchQuery.isNotEmpty) {
          if (!task.text.toLowerCase().contains(_searchQuery.toLowerCase())) {
            return false;
          }
        }
        
        // Apply status filter
        switch (_currentFilter) {
          case TaskFilter.all:
            return true;
          case TaskFilter.active:
            return !task.done;
          case TaskFilter.completed:
            return task.done;
        }
      }).toList();
    });
  }

  void _addTask() {
    final text = _taskController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('Task cannot be empty!', isError: true);
      return;
    }
    
    setState(() {
      _tasks.insert(0, Task(
        text: text,
        done: false,
        createdAt: DateTime.now(),
        priority: TaskPriority.medium,
      ));
      _taskController.clear();
      _applyFilters();
    });
    _saveTasks();
    _showSnackBar('Task added successfully!');
  }

  void _toggleDone(int index) {
    final taskIndex = _tasks.indexWhere((t) => t.id == _filteredTasks[index].id);
    if (taskIndex != -1) {
      setState(() {
        _tasks[taskIndex].done = !_tasks[taskIndex].done;
        _tasks[taskIndex].completedAt = _tasks[taskIndex].done ? DateTime.now() : null;
        _applyFilters();
      });
      _saveTasks();
    }
  }

  void _deleteTask(int index) {
    final taskIndex = _tasks.indexWhere((t) => t.id == _filteredTasks[index].id);
    if (taskIndex != -1) {
      setState(() {
        _recentlyDeletedTask = _tasks.removeAt(taskIndex);
        _recentlyDeletedTaskIndex = taskIndex;
        _applyFilters();
      });
      _saveTasks();
      _showSnackBar(
        'Deleted "${_recentlyDeletedTask!.text}"',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (_recentlyDeletedTask != null && _recentlyDeletedTaskIndex != null) {
              setState(() {
                _tasks.insert(_recentlyDeletedTaskIndex!, _recentlyDeletedTask!);
                _applyFilters();
              });
              _saveTasks();
            }
          },
        ),
      );
    }
  }

  void _editTask(int index) {
    final task = _filteredTasks[index];
    _taskController.text = task.text;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskEditSheet(
        task: task,
        onSave: (updatedTask) {
          final taskIndex = _tasks.indexWhere((t) => t.id == task.id);
          if (taskIndex != -1) {
            setState(() {
              _tasks[taskIndex] = updatedTask;
              _applyFilters();
            });
            _saveTasks();
            _showSnackBar('Task updated successfully!');
          }
        },
      ),
    );
  }

  void _deleteAllCompleted() {
    if (_completedTasks == 0) {
      _showSnackBar('No completed tasks to delete!');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Completed Tasks'),
        content: Text('Are you sure you want to delete $_completedTasks completed task${_completedTasks == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _tasks.removeWhere((task) => task.done);
                _applyFilters();
              });
              _saveTasks();
              Navigator.of(context).pop();
              _showSnackBar('Completed tasks deleted!');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _markAllAsDone() {
    if (_activeTasks == 0) {
      _showSnackBar('No active tasks to mark as done!');
      return;
    }
    
    setState(() {
      for (var task in _tasks) {
        if (!task.done) {
          task.done = true;
          task.completedAt = DateTime.now();
        }
      }
      _applyFilters();
    });
    _saveTasks();
    _showSnackBar('All tasks marked as completed!');
  }

  void _showSnackBar(String message, {bool isError = false, SnackBarAction? action}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        action: action,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Smart ToDo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        actions: [
          if (_tasks.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'delete_completed':
                    _deleteAllCompleted();
                    break;
                  case 'mark_all_done':
                    _markAllAsDone();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'mark_all_done',
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline),
                      SizedBox(width: 8),
                      Text('Mark all as done'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete_completed',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep),
                      SizedBox(width: 8),
                      Text('Delete completed'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Statistics Card
          if (_tasks.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: 'Total',
                      value: _totalTasks.toString(),
                      icon: Icons.list_alt,
                      color: colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: 'Active',
                      value: _activeTasks.toString(),
                      icon: Icons.pending,
                      color: Colors.orange,
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: 'Done',
                      value: _completedTasks.toString(),
                      icon: Icons.check_circle,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          
          // Progress Bar
          if (_tasks.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${(_completionRate * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _completionRate,
                    backgroundColor: colorScheme.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          
          // Search Bar
          if (_tasks.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search tasks...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _applyFilters();
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _applyFilters();
                  });
                },
              ),
            ),
          
          // Filter Chips
          if (_tasks.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: TaskFilter.values.map((filter) {
                    final isSelected = _currentFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filter.displayName),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _currentFilter = filter;
                            _applyFilters();
                          });
                        },
                        backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
                        selectedColor: colorScheme.primaryContainer,
                        checkmarkColor: colorScheme.primary,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Task Input
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskController,
                    decoration: InputDecoration(
                      hintText: 'Add a new task...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addTask(),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  onPressed: _addTask,
                  mini: true,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Task List
          Expanded(
            child: _filteredTasks.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredTasks.length,
                    itemBuilder: (context, index) {
                      final task = _filteredTasks[index];
                      return _TaskCard(
                        task: task,
                        onToggle: () => _toggleDone(index),
                        onDelete: () => _deleteTask(index),
                        onEdit: () => _editTask(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.task_alt,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks yet!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first task to get started',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks found',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _TaskCard({
    required this.task,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOverdue = task.dueDate != null && 
                     task.dueDate!.isBefore(DateTime.now()) && 
                     !task.done;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue 
              ? Colors.red.withOpacity(0.3)
              : colorScheme.outline.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Checkbox(
          value: task.done,
          onChanged: (_) => onToggle(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(
          task.text,
          style: TextStyle(
            decoration: task.done ? TextDecoration.lineThrough : null,
            color: task.done ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
            fontWeight: task.done ? FontWeight.normal : FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.dueDate != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: isOverdue ? Colors.red : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(task.dueDate!),
                    style: TextStyle(
                      fontSize: 12,
                      color: isOverdue ? Colors.red : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            if (task.priority != TaskPriority.medium) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    task.priority == TaskPriority.high 
                        ? Icons.priority_high 
                        : Icons.low_priority,
                    size: 14,
                    color: task.priority == TaskPriority.high 
                        ? Colors.red 
                        : Colors.green,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    task.priority.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: task.priority == TaskPriority.high 
                          ? Colors.red 
                          : Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
              color: colorScheme.primary,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final taskDate = DateTime(date.year, date.month, date.day);
    
    if (taskDate == today) {
      return 'Today';
    } else if (taskDate == tomorrow) {
      return 'Tomorrow';
    } else if (taskDate.isBefore(today)) {
      return 'Overdue';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class TaskEditSheet extends StatefulWidget {
  final Task task;
  final Function(Task) onSave;

  const TaskEditSheet({
    super.key,
    required this.task,
    required this.onSave,
  });

  @override
  State<TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends State<TaskEditSheet> {
  late TextEditingController _textController;
  late TaskPriority _priority;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.task.text);
    _priority = widget.task.priority;
    _dueDate = widget.task.dueDate;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Edit Task',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _textController,
            decoration: const InputDecoration(
              labelText: 'Task description',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Priority',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: TaskPriority.values.map((priority) {
              return ChoiceChip(
                label: Text(priority.displayName),
                selected: _priority == priority,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _priority = priority;
                    });
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Due Date',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() {
                      _dueDate = date;
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(_dueDate == null ? 'Set due date' : 'Change date'),
              ),
            ],
          ),
          if (_dueDate != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Due: ${_formatDate(_dueDate!)}',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _dueDate = null;
                      });
                    },
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final updatedTask = Task(
                      id: widget.task.id,
                      text: _textController.text.trim(),
                      done: widget.task.done,
                      createdAt: widget.task.createdAt,
                      completedAt: widget.task.completedAt,
                      priority: _priority,
                      dueDate: _dueDate,
                    );
                    widget.onSave(updatedTask);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

enum TaskFilter { all, active, completed }

extension TaskFilterExtension on TaskFilter {
  String get displayName {
    switch (this) {
      case TaskFilter.all:
        return 'All';
      case TaskFilter.active:
        return 'Active';
      case TaskFilter.completed:
        return 'Completed';
    }
  }
}

enum TaskPriority { low, medium, high }

extension TaskPriorityExtension on TaskPriority {
  String get displayName {
    switch (this) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.high:
        return 'High';
    }
  }
}

class Task {
  final String id;
  String text;
  bool done;
  final DateTime createdAt;
  DateTime? completedAt;
  TaskPriority priority;
  DateTime? dueDate;

  Task({
    String? id,
    required this.text,
    required this.done,
    DateTime? createdAt,
    this.completedAt,
    this.priority = TaskPriority.medium,
    this.dueDate,
  }) : 
    id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
    createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'done': done,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'priority': priority.index,
    'dueDate': dueDate?.toIso8601String(),
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'],
    text: json['text'],
    done: json['done'],
    createdAt: DateTime.parse(json['createdAt']),
    completedAt: json['completedAt'] != null 
        ? DateTime.parse(json['completedAt']) 
        : null,
    priority: TaskPriority.values[json['priority'] ?? 1],
    dueDate: json['dueDate'] != null 
        ? DateTime.parse(json['dueDate']) 
        : null,
  );
}
