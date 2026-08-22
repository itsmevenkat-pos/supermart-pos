// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cart_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$cartHash() => r'e14c224db6db6ad9aa54c3f9ee577b52e6cf286d';

/// See also [Cart].
@ProviderFor(Cart)
final cartProvider = AutoDisposeNotifierProvider<Cart, List<CartItem>>.internal(
  Cart.new,
  name: r'cartProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$cartHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Cart = AutoDisposeNotifier<List<CartItem>>;
String _$billWorkspaceHash() => r'ed9975b23ed60e6a607d3b8bb6e137a90b628c85';

/// See also [BillWorkspace].
@ProviderFor(BillWorkspace)
final billWorkspaceProvider =
    AutoDisposeNotifierProvider<BillWorkspace, BillWorkspaceState>.internal(
  BillWorkspace.new,
  name: r'billWorkspaceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$billWorkspaceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$BillWorkspace = AutoDisposeNotifier<BillWorkspaceState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
