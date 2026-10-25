import 'package:flutter/material.dart';

class ModelSelector extends StatelessWidget {
  const ModelSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      onChanged: onChanged,
      hint: hint != null ? Text(hint!) : null,
      items: const [
        DropdownMenuItem(
            value: 'LinearRegression', child: Text('Linear Regression')),
        DropdownMenuItem(
            value: 'DecisionTreeRegressor',
            child: Text('Decision Tree Regressor')),
        DropdownMenuItem(value: 'RidgeCV', child: Text('Ridge CV')),
        DropdownMenuItem(value: 'LassoCV', child: Text('Lasso CV')),
        DropdownMenuItem(value: 'ElasticNetCV', child: Text('ElasticNet CV')),
        DropdownMenuItem(
            value: 'RandomForestRegressor',
            child: Text('Random Forest Regressor')),
        DropdownMenuItem(
            value: 'ExtraTreesRegressor', child: Text('Extra Trees Regressor')),
        DropdownMenuItem(
            value: 'VotingRegressor', child: Text('Voting Regressor')),
        DropdownMenuItem(
            value: 'StackingRegressor', child: Text('Stacking Regressor')),
        DropdownMenuItem(
            value: 'RandomForestRegressor_Tuned',
            child: Text('Random Forest (Tuned)')),
        DropdownMenuItem(
            value: 'GradientBoostingRegressor_Tuned',
            child: Text('Gradient Boosting (Tuned)')),
      ],
      decoration: InputDecoration(
        labelText: 'Model',
        prefixIcon: const Icon(Icons.psychology),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please select a model';
        }
        return null;
      },
    );
  }
}
