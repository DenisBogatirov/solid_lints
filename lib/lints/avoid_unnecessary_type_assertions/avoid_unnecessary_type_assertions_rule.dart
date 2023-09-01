import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:collection/collection.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:solid_lints/models/rule_config.dart';
import 'package:solid_lints/models/solid_lint_rule.dart';
import 'package:solid_lints/utils/typecast_utils.dart';
import 'package:solid_lints/utils/types_utils.dart';

part 'avoid_unnecessary_type_assertions_fix.dart';

/// The name of 'is' operator
const operatorIsName = 'is';

/// The name of 'whereType' method
const whereTypeMethodName = 'whereType';

/// A `avoid-unnecessary-type-assertions` rule which
/// warns about unnecessary usage of `is` and `whereType` operators
class AvoidUnnecessaryTypeAssertions extends SolidLintRule {
  /// The [LintCode] of this lint rule that represents
  /// the error whether we use bad formatted double literals.
  static const lintName = 'avoid-unnecessary-type-assertions';

  static const _unnecessaryIsCode = LintCode(
    name: lintName,
    problemMessage: "Unnecessary usage of the '$operatorIsName' operator.",
  );

  static const _unnecessaryWhereTypeCode = LintCode(
    name: lintName,
    problemMessage: "Unnecessary usage of the '$whereTypeMethodName' method.",
  );

  AvoidUnnecessaryTypeAssertions._(super.config);

  /// Creates a new instance of [AvoidUnnecessaryTypeAssertions]
  /// based on the lint configuration.
  factory AvoidUnnecessaryTypeAssertions.createRule(CustomLintConfigs configs) {
    final rule = RuleConfig(
      configs: configs,
      name: lintName,
      problemMessage: (_) => "Unnecessary usage of typecast operators.",
    );

    return AvoidUnnecessaryTypeAssertions._(rule);
  }

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addIsExpression((node) {
      if (_isUnnecessaryIsExpression(node)) {
        reporter.reportErrorForNode(_unnecessaryIsCode, node);
      }
    });

    context.registry.addMethodInvocation((node) {
      if (_isUnnecessaryWhereType(node)) {
        reporter.reportErrorForNode(_unnecessaryWhereTypeCode, node);
      }
    });
  }

  @override
  List<Fix> getFixes() => [_UnnecessaryTypeAssertionsFix()];

  bool _isUnnecessaryIsExpression(IsExpression node) {
    final objectType = node.expression.staticType;
    final castedType = node.type.type;

    if (node.notOperator != null &&
        objectType != null &&
        objectType is! TypeParameterType &&
        objectType is! DynamicType &&
        !objectType.isDartCoreObject &&
        _isUnnecessaryTypeCheck(objectType, castedType, isReversed: true)) {
      return true;
    } else {
      return _isUnnecessaryTypeCheck(objectType, castedType);
    }
  }

  bool _isUnnecessaryWhereType(MethodInvocation node) {
    if (node
        case MethodInvocation(
          methodName: Identifier(name: whereTypeMethodName),
          target: Expression(staticType: final targetType),
          realTarget: Expression(staticType: final realTargetType),
          typeArguments: TypeArgumentList(arguments: final arguments),
        )
        when targetType is ParameterizedType &&
            isIterable(realTargetType) &&
            arguments.isNotEmpty) {
      return _isUnnecessaryTypeCheck(
        targetType.typeArguments.first,
        arguments.first.type,
      );
    } else {
      return false;
    }
  }

  /// Checks that type checking is unnecessary
  /// [objectType] is the source expression type
  /// [castedType] is the type against which the expression type is compared
  /// [isReversed] true for opposite comparison, i.e 'is!'
  /// and false for positive comparison, i.e. 'is' or 'whereType'
  bool _isUnnecessaryTypeCheck(
    DartType? objectType,
    DartType? castedType, {
    bool isReversed = false,
  }) {
    if (objectType == null || castedType == null) {
      return false;
    }

    final typeCast = TypeCast(
      source: objectType,
      target: castedType,
    );

    if (_isNullableCompatibility(typeCast)) {
      return false;
    }

    final objectCastedType = typeCast.castTypeInHierarchy();

    if (objectCastedType == null) {
      return isReversed;
    }

    final objectTypeCast = TypeCast(
      source: objectCastedType,
      target: castedType,
    );
    if (!_areGenericsWithSameTypeArgs(objectTypeCast)) {
      return false;
    }

    return !isReversed;
  }

  bool _isNullableCompatibility(TypeCast typeCast) {
    final isObjectTypeNullable = isNullableType(typeCast.source);
    final isCastedTypeNullable = isNullableType(typeCast.target);

    // Only one case `Type? is Type` always valid assertion case.
    return isObjectTypeNullable && !isCastedTypeNullable;
  }

  bool _areGenericsWithSameTypeArgs(TypeCast typeCast) {
    if (typeCast
        case TypeCast(source: final objectType, target: final castedType)
        when objectType is ParameterizedType &&
            castedType is ParameterizedType) {
      if (objectType.typeArguments.length != castedType.typeArguments.length) {
        return false;
      }

      return IterableZip([objectType.typeArguments, castedType.typeArguments])
          .every((e) => _isUnnecessaryTypeCheck(e[0], e[1]));
    } else {
      return false;
    }
  }
}
