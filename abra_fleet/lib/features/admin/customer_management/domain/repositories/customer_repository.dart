// File: lib/features/admin/customer_management/domain/repositories/customer_repository.dart
// Defines the contract for customer data operations.

import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart'; // Import your Customer entity

abstract class CustomerRepository {
  // Get a list of all customers.
  Future<List<CustomerEntity>> getCustomers();

  // Get a specific customer by their ID.
  Future<CustomerEntity?> getCustomerById(String id);

  // Add a new customer.
  // Returns the newly added customer (possibly with a server-generated ID).
  Future<CustomerEntity> addCustomer(CustomerEntity customer);

  // Update an existing customer.
  Future<void> updateCustomer(CustomerEntity customer);

  // Delete a customer by their ID.
  Future<void> deleteCustomer(String id);
}
