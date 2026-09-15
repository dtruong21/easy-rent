// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'onboarding_progress.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$OnboardingProgress {
  bool get hasProperty => throw _privateConstructorUsedError;
  bool get hasTenant => throw _privateConstructorUsedError;
  bool get hasLease => throw _privateConstructorUsedError;
  bool get hasPayment => throw _privateConstructorUsedError;
  bool get hasReceipt => throw _privateConstructorUsedError;
  String? get firstLeaseId => throw _privateConstructorUsedError;

  /// Create a copy of OnboardingProgress
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OnboardingProgressCopyWith<OnboardingProgress> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OnboardingProgressCopyWith<$Res> {
  factory $OnboardingProgressCopyWith(
    OnboardingProgress value,
    $Res Function(OnboardingProgress) then,
  ) = _$OnboardingProgressCopyWithImpl<$Res, OnboardingProgress>;
  @useResult
  $Res call({
    bool hasProperty,
    bool hasTenant,
    bool hasLease,
    bool hasPayment,
    bool hasReceipt,
    String? firstLeaseId,
  });
}

/// @nodoc
class _$OnboardingProgressCopyWithImpl<$Res, $Val extends OnboardingProgress>
    implements $OnboardingProgressCopyWith<$Res> {
  _$OnboardingProgressCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OnboardingProgress
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? hasProperty = null,
    Object? hasTenant = null,
    Object? hasLease = null,
    Object? hasPayment = null,
    Object? hasReceipt = null,
    Object? firstLeaseId = freezed,
  }) {
    return _then(
      _value.copyWith(
            hasProperty: null == hasProperty
                ? _value.hasProperty
                : hasProperty // ignore: cast_nullable_to_non_nullable
                      as bool,
            hasTenant: null == hasTenant
                ? _value.hasTenant
                : hasTenant // ignore: cast_nullable_to_non_nullable
                      as bool,
            hasLease: null == hasLease
                ? _value.hasLease
                : hasLease // ignore: cast_nullable_to_non_nullable
                      as bool,
            hasPayment: null == hasPayment
                ? _value.hasPayment
                : hasPayment // ignore: cast_nullable_to_non_nullable
                      as bool,
            hasReceipt: null == hasReceipt
                ? _value.hasReceipt
                : hasReceipt // ignore: cast_nullable_to_non_nullable
                      as bool,
            firstLeaseId: freezed == firstLeaseId
                ? _value.firstLeaseId
                : firstLeaseId // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OnboardingProgressImplCopyWith<$Res>
    implements $OnboardingProgressCopyWith<$Res> {
  factory _$$OnboardingProgressImplCopyWith(
    _$OnboardingProgressImpl value,
    $Res Function(_$OnboardingProgressImpl) then,
  ) = __$$OnboardingProgressImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    bool hasProperty,
    bool hasTenant,
    bool hasLease,
    bool hasPayment,
    bool hasReceipt,
    String? firstLeaseId,
  });
}

/// @nodoc
class __$$OnboardingProgressImplCopyWithImpl<$Res>
    extends _$OnboardingProgressCopyWithImpl<$Res, _$OnboardingProgressImpl>
    implements _$$OnboardingProgressImplCopyWith<$Res> {
  __$$OnboardingProgressImplCopyWithImpl(
    _$OnboardingProgressImpl _value,
    $Res Function(_$OnboardingProgressImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OnboardingProgress
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? hasProperty = null,
    Object? hasTenant = null,
    Object? hasLease = null,
    Object? hasPayment = null,
    Object? hasReceipt = null,
    Object? firstLeaseId = freezed,
  }) {
    return _then(
      _$OnboardingProgressImpl(
        hasProperty: null == hasProperty
            ? _value.hasProperty
            : hasProperty // ignore: cast_nullable_to_non_nullable
                  as bool,
        hasTenant: null == hasTenant
            ? _value.hasTenant
            : hasTenant // ignore: cast_nullable_to_non_nullable
                  as bool,
        hasLease: null == hasLease
            ? _value.hasLease
            : hasLease // ignore: cast_nullable_to_non_nullable
                  as bool,
        hasPayment: null == hasPayment
            ? _value.hasPayment
            : hasPayment // ignore: cast_nullable_to_non_nullable
                  as bool,
        hasReceipt: null == hasReceipt
            ? _value.hasReceipt
            : hasReceipt // ignore: cast_nullable_to_non_nullable
                  as bool,
        firstLeaseId: freezed == firstLeaseId
            ? _value.firstLeaseId
            : firstLeaseId // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$OnboardingProgressImpl extends _OnboardingProgress {
  const _$OnboardingProgressImpl({
    required this.hasProperty,
    required this.hasTenant,
    required this.hasLease,
    required this.hasPayment,
    required this.hasReceipt,
    required this.firstLeaseId,
  }) : super._();

  @override
  final bool hasProperty;
  @override
  final bool hasTenant;
  @override
  final bool hasLease;
  @override
  final bool hasPayment;
  @override
  final bool hasReceipt;
  @override
  final String? firstLeaseId;

  @override
  String toString() {
    return 'OnboardingProgress(hasProperty: $hasProperty, hasTenant: $hasTenant, hasLease: $hasLease, hasPayment: $hasPayment, hasReceipt: $hasReceipt, firstLeaseId: $firstLeaseId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OnboardingProgressImpl &&
            (identical(other.hasProperty, hasProperty) ||
                other.hasProperty == hasProperty) &&
            (identical(other.hasTenant, hasTenant) ||
                other.hasTenant == hasTenant) &&
            (identical(other.hasLease, hasLease) ||
                other.hasLease == hasLease) &&
            (identical(other.hasPayment, hasPayment) ||
                other.hasPayment == hasPayment) &&
            (identical(other.hasReceipt, hasReceipt) ||
                other.hasReceipt == hasReceipt) &&
            (identical(other.firstLeaseId, firstLeaseId) ||
                other.firstLeaseId == firstLeaseId));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    hasProperty,
    hasTenant,
    hasLease,
    hasPayment,
    hasReceipt,
    firstLeaseId,
  );

  /// Create a copy of OnboardingProgress
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OnboardingProgressImplCopyWith<_$OnboardingProgressImpl> get copyWith =>
      __$$OnboardingProgressImplCopyWithImpl<_$OnboardingProgressImpl>(
        this,
        _$identity,
      );
}

abstract class _OnboardingProgress extends OnboardingProgress {
  const factory _OnboardingProgress({
    required final bool hasProperty,
    required final bool hasTenant,
    required final bool hasLease,
    required final bool hasPayment,
    required final bool hasReceipt,
    required final String? firstLeaseId,
  }) = _$OnboardingProgressImpl;
  const _OnboardingProgress._() : super._();

  @override
  bool get hasProperty;
  @override
  bool get hasTenant;
  @override
  bool get hasLease;
  @override
  bool get hasPayment;
  @override
  bool get hasReceipt;
  @override
  String? get firstLeaseId;

  /// Create a copy of OnboardingProgress
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OnboardingProgressImplCopyWith<_$OnboardingProgressImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
