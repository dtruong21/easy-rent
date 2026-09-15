// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dashboard_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$DashboardSnapshot {
  LoyersMoisKpi get loyers => throw _privateConstructorUsedError;
  RetardsKpi get retards => throw _privateConstructorUsedError;
  DocsPendingKpi get docs => throw _privateConstructorUsedError;
  List<ActivityItem> get activity => throw _privateConstructorUsedError;
  OnboardingProgress? get onboarding => throw _privateConstructorUsedError;

  /// Create a copy of DashboardSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DashboardSnapshotCopyWith<DashboardSnapshot> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DashboardSnapshotCopyWith<$Res> {
  factory $DashboardSnapshotCopyWith(
    DashboardSnapshot value,
    $Res Function(DashboardSnapshot) then,
  ) = _$DashboardSnapshotCopyWithImpl<$Res, DashboardSnapshot>;
  @useResult
  $Res call({
    LoyersMoisKpi loyers,
    RetardsKpi retards,
    DocsPendingKpi docs,
    List<ActivityItem> activity,
    OnboardingProgress? onboarding,
  });

  $LoyersMoisKpiCopyWith<$Res> get loyers;
  $RetardsKpiCopyWith<$Res> get retards;
  $DocsPendingKpiCopyWith<$Res> get docs;
  $OnboardingProgressCopyWith<$Res>? get onboarding;
}

/// @nodoc
class _$DashboardSnapshotCopyWithImpl<$Res, $Val extends DashboardSnapshot>
    implements $DashboardSnapshotCopyWith<$Res> {
  _$DashboardSnapshotCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DashboardSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? loyers = null,
    Object? retards = null,
    Object? docs = null,
    Object? activity = null,
    Object? onboarding = freezed,
  }) {
    return _then(
      _value.copyWith(
            loyers: null == loyers
                ? _value.loyers
                : loyers // ignore: cast_nullable_to_non_nullable
                      as LoyersMoisKpi,
            retards: null == retards
                ? _value.retards
                : retards // ignore: cast_nullable_to_non_nullable
                      as RetardsKpi,
            docs: null == docs
                ? _value.docs
                : docs // ignore: cast_nullable_to_non_nullable
                      as DocsPendingKpi,
            activity: null == activity
                ? _value.activity
                : activity // ignore: cast_nullable_to_non_nullable
                      as List<ActivityItem>,
            onboarding: freezed == onboarding
                ? _value.onboarding
                : onboarding // ignore: cast_nullable_to_non_nullable
                      as OnboardingProgress?,
          )
          as $Val,
    );
  }

  /// Create a copy of DashboardSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $LoyersMoisKpiCopyWith<$Res> get loyers {
    return $LoyersMoisKpiCopyWith<$Res>(_value.loyers, (value) {
      return _then(_value.copyWith(loyers: value) as $Val);
    });
  }

  /// Create a copy of DashboardSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $RetardsKpiCopyWith<$Res> get retards {
    return $RetardsKpiCopyWith<$Res>(_value.retards, (value) {
      return _then(_value.copyWith(retards: value) as $Val);
    });
  }

  /// Create a copy of DashboardSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $DocsPendingKpiCopyWith<$Res> get docs {
    return $DocsPendingKpiCopyWith<$Res>(_value.docs, (value) {
      return _then(_value.copyWith(docs: value) as $Val);
    });
  }

  /// Create a copy of DashboardSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $OnboardingProgressCopyWith<$Res>? get onboarding {
    if (_value.onboarding == null) {
      return null;
    }

    return $OnboardingProgressCopyWith<$Res>(_value.onboarding!, (value) {
      return _then(_value.copyWith(onboarding: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$DashboardSnapshotImplCopyWith<$Res>
    implements $DashboardSnapshotCopyWith<$Res> {
  factory _$$DashboardSnapshotImplCopyWith(
    _$DashboardSnapshotImpl value,
    $Res Function(_$DashboardSnapshotImpl) then,
  ) = __$$DashboardSnapshotImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    LoyersMoisKpi loyers,
    RetardsKpi retards,
    DocsPendingKpi docs,
    List<ActivityItem> activity,
    OnboardingProgress? onboarding,
  });

  @override
  $LoyersMoisKpiCopyWith<$Res> get loyers;
  @override
  $RetardsKpiCopyWith<$Res> get retards;
  @override
  $DocsPendingKpiCopyWith<$Res> get docs;
  @override
  $OnboardingProgressCopyWith<$Res>? get onboarding;
}

/// @nodoc
class __$$DashboardSnapshotImplCopyWithImpl<$Res>
    extends _$DashboardSnapshotCopyWithImpl<$Res, _$DashboardSnapshotImpl>
    implements _$$DashboardSnapshotImplCopyWith<$Res> {
  __$$DashboardSnapshotImplCopyWithImpl(
    _$DashboardSnapshotImpl _value,
    $Res Function(_$DashboardSnapshotImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DashboardSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? loyers = null,
    Object? retards = null,
    Object? docs = null,
    Object? activity = null,
    Object? onboarding = freezed,
  }) {
    return _then(
      _$DashboardSnapshotImpl(
        loyers: null == loyers
            ? _value.loyers
            : loyers // ignore: cast_nullable_to_non_nullable
                  as LoyersMoisKpi,
        retards: null == retards
            ? _value.retards
            : retards // ignore: cast_nullable_to_non_nullable
                  as RetardsKpi,
        docs: null == docs
            ? _value.docs
            : docs // ignore: cast_nullable_to_non_nullable
                  as DocsPendingKpi,
        activity: null == activity
            ? _value._activity
            : activity // ignore: cast_nullable_to_non_nullable
                  as List<ActivityItem>,
        onboarding: freezed == onboarding
            ? _value.onboarding
            : onboarding // ignore: cast_nullable_to_non_nullable
                  as OnboardingProgress?,
      ),
    );
  }
}

/// @nodoc

class _$DashboardSnapshotImpl extends _DashboardSnapshot {
  const _$DashboardSnapshotImpl({
    required this.loyers,
    required this.retards,
    required this.docs,
    required final List<ActivityItem> activity,
    this.onboarding,
  }) : _activity = activity,
       super._();

  @override
  final LoyersMoisKpi loyers;
  @override
  final RetardsKpi retards;
  @override
  final DocsPendingKpi docs;
  final List<ActivityItem> _activity;
  @override
  List<ActivityItem> get activity {
    if (_activity is EqualUnmodifiableListView) return _activity;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_activity);
  }

  @override
  final OnboardingProgress? onboarding;

  @override
  String toString() {
    return 'DashboardSnapshot(loyers: $loyers, retards: $retards, docs: $docs, activity: $activity, onboarding: $onboarding)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DashboardSnapshotImpl &&
            (identical(other.loyers, loyers) || other.loyers == loyers) &&
            (identical(other.retards, retards) || other.retards == retards) &&
            (identical(other.docs, docs) || other.docs == docs) &&
            const DeepCollectionEquality().equals(other._activity, _activity) &&
            (identical(other.onboarding, onboarding) ||
                other.onboarding == onboarding));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    loyers,
    retards,
    docs,
    const DeepCollectionEquality().hash(_activity),
    onboarding,
  );

  /// Create a copy of DashboardSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DashboardSnapshotImplCopyWith<_$DashboardSnapshotImpl> get copyWith =>
      __$$DashboardSnapshotImplCopyWithImpl<_$DashboardSnapshotImpl>(
        this,
        _$identity,
      );
}

abstract class _DashboardSnapshot extends DashboardSnapshot {
  const factory _DashboardSnapshot({
    required final LoyersMoisKpi loyers,
    required final RetardsKpi retards,
    required final DocsPendingKpi docs,
    required final List<ActivityItem> activity,
    final OnboardingProgress? onboarding,
  }) = _$DashboardSnapshotImpl;
  const _DashboardSnapshot._() : super._();

  @override
  LoyersMoisKpi get loyers;
  @override
  RetardsKpi get retards;
  @override
  DocsPendingKpi get docs;
  @override
  List<ActivityItem> get activity;
  @override
  OnboardingProgress? get onboarding;

  /// Create a copy of DashboardSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DashboardSnapshotImplCopyWith<_$DashboardSnapshotImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
