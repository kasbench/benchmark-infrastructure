# =============================================================================
# Environment Description Module - Outputs
# =============================================================================

output "json_path" {
  description = "Absolute path to the generated JSON environment description file"
  value       = local_file.environment_json.filename
}

output "markdown_path" {
  description = "Absolute path to the generated Markdown environment description file"
  value       = local_file.environment_md.filename
}

output "checksums_path" {
  description = "Absolute path to the generated checksums JSON file"
  value       = local_file.checksums.filename
}
