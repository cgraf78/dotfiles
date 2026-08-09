# C++ Style

<!-- agent-rule-id: language-cpp-style -->
<!-- agent-rule-trigger: Editing C++ -->

- `std::unique_ptr` for single ownership, `std::shared_ptr` only when truly
  shared.
- References (`const T&`, `T&`) for non-owning params. `std::span<T>` for
  contiguous data views. Never raw pointers.
- `std::optional<std::reference_wrapper<T>>` for optional non-owning refs.
- Always brace-initialize variables (`int count{};`). Initialize at declaration.
- `auto` when type is obvious from context, explicit otherwise.
- `constexpr` for compile-time constants, `std::string_view` for read-only
  strings, `std::optional` over sentinel values.
- `[[nodiscard]]` on getters and functions returning values.
- `std::expected` / `folly::Expected` for expected failures, `std::optional` for
  "not found", exceptions for truly exceptional cases.
