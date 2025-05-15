{% macro export_csv(model_name, file_path) %}
  {{ log("WARNING: export_csv is a placeholder. Data export in Oracle requires database privileges.", info=True) }}
  {{ log("Target file path: " ~ file_path, info=True) }}

  -- Return an empty string to allow the model to compile
  {{ return('') }}
{% endmacro %}
