data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_subnet" "runners" {
  id = length(var.subnet_id) > 0 ? var.subnet_id : var.subnet_id_runners
}

data "aws_availability_zone" "runners" {
  name = data.aws_subnet.runners.availability_zone
}

# Parameter value is managed by the user-data script of the gitlab runner instance
resource "aws_ssm_parameter" "runner_registration_token" {
  name  = local.secure_parameter_store_runner_token_key
  type  = "SecureString"
  value = "null"

  tags = local.tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "runner_sentry_dsn" {
  name  = local.secure_parameter_store_runner_sentry_dsn
  type  = "SecureString"
  value = "null"

  tags = local.tags

  lifecycle {
    ignore_changes = [value]
  }
}

locals {
  template_user_data = templatefile("${path.module}/template/user-data.tpl",
    {
      eip                 = var.enable_eip ? local.template_eip : ""
      logging             = var.enable_cloudwatch_logging ? local.logging_user_data : ""
      gitlab_runner       = local.template_gitlab_runner
      user_data_trace_log = var.enable_runner_user_data_trace_log
      yum_update          = var.runner_yum_update ? local.file_yum_update : ""
      extra_config        = var.runner_extra_config
  })

  file_yum_update = file("${path.module}/template/yum_update.tpl")

  template_eip = templatefile("${path.module}/template/eip.tpl", {
    eip = join(",", [for eip in aws_eip.gitlab_runner : eip.public_ip])
  })

  template_gitlab_runner = templatefile("${path.module}/template/gitlab-runner.tpl",
    {
      gitlab_runner_version                        = var.gitlab_runner_version
      docker_machine_version                       = var.docker_machine_version
      docker_machine_download_url                  = var.docker_machine_download_url
      runners_config                               = local.template_runner_config
      runners_userdata                             = var.runners_userdata
      runners_executor                             = var.runners_executor
      runners_install_amazon_ecr_credential_helper = var.runners_install_amazon_ecr_credential_helper
      curl_cacert                                  = length(var.runners_gitlab_certificate) > 0 ? "--cacert /etc/gitlab-runner/certs/gitlab.crt" : ""
      pre_install_certificates                     = local.pre_install_certificates
      pre_install                                  = var.userdata_pre_install
      post_install                                 = var.userdata_post_install
      runners_gitlab_url                           = var.runners_gitlab_url
      runners_token                                = var.runners_token
      secure_parameter_store_runner_token_key      = local.secure_parameter_store_runner_token_key
      secure_parameter_store_runner_sentry_dsn     = local.secure_parameter_store_runner_sentry_dsn
      secure_parameter_store_region                = var.aws_region
      gitlab_runner_registration_token             = var.gitlab_runner_registration_config["registration_token"]
      gitlab_runner_description                    = var.gitlab_runner_registration_config["description"]
      gitlab_runner_tag_list                       = var.gitlab_runner_registration_config["tag_list"]
      gitlab_runner_locked_to_project              = var.gitlab_runner_registration_config["locked_to_project"]
      gitlab_runner_run_untagged                   = var.gitlab_runner_registration_config["run_untagged"]
      gitlab_runner_maximum_timeout                = var.gitlab_runner_registration_config["maximum_timeout"]
      gitlab_runner_access_level                   = lookup(var.gitlab_runner_registration_config, "access_level", "not_protected")
      sentry_dsn                                   = var.sentry_dsn
  })

  template_runner_config = templatefile("${path.module}/template/runner-config.tpl",
    {
      aws_region                        = var.aws_region
      gitlab_url                        = var.runners_gitlab_url
      gitlab_clone_url                  = var.runners_clone_url
      tls_ca_file                       = length(var.runners_gitlab_certificate) > 0 ? "tls-ca-file=\"/etc/gitlab-runner/certs/gitlab.crt\"" : ""
      runners_extra_hosts               = var.runners_extra_hosts
      runners_vpc_id                    = var.vpc_id
      runners_subnet_id                 = length(var.subnet_id) > 0 ? var.subnet_id : var.subnet_id_runners
      runners_aws_zone                  = data.aws_availability_zone.runners.name_suffix
      runners_instance_type             = var.docker_machine_instance_type
      runners_spot_price_bid            = var.docker_machine_spot_price_bid == "on-demand-price" || var.docker_machine_spot_price_bid == null ? "" : var.docker_machine_spot_price_bid
      runners_ami                       = var.runners_executor == "docker+machine" ? data.aws_ami.docker-machine[0].id : ""
      runners_security_group_name       = var.runners_executor == "docker+machine" ? aws_security_group.docker_machine[0].name : ""
      runners_monitoring                = var.runners_monitoring
      runners_ebs_optimized             = var.runners_ebs_optimized
      runners_instance_profile          = var.runners_executor == "docker+machine" ? aws_iam_instance_profile.docker_machine[0].name : ""
      runners_additional_volumes        = local.runners_additional_volumes
      docker_machine_options            = length(local.docker_machine_options_string) == 1 ? "" : local.docker_machine_options_string
      docker_machine_name               = format("%s-%s", local.runner_tags_merged["Name"], "%s") # %s is always needed
      runners_name                      = var.runners_name
      runners_tags                      = replace(replace(local.runner_tags_string, ",,", ","), "/,$/", "")
      runners_token                     = var.runners_token
      runners_userdata                  = var.runners_userdata
      runners_executor                  = var.runners_executor
      runners_limit                     = var.runners_limit
      runners_concurrent                = var.runners_concurrent
      runners_image                     = var.runners_image
      runners_privileged                = var.runners_privileged
      runners_disable_cache             = var.runners_disable_cache
      runners_docker_runtime            = var.runners_docker_runtime
      runners_helper_image              = var.runners_helper_image
      runners_shm_size                  = var.runners_shm_size
      runners_pull_policies             = local.runners_pull_policies
      runners_idle_count                = var.runners_idle_count
      runners_idle_time                 = var.runners_idle_time
      runners_max_builds                = local.runners_max_builds_string
      runners_machine_autoscaling       = local.runners_machine_autoscaling
      runners_root_size                 = var.runners_root_size
      runners_volume_type               = var.runners_volume_type
      runners_iam_instance_profile_name = var.runners_iam_instance_profile_name
      runners_use_private_address_only  = var.runners_use_private_address
      runners_use_private_address       = !var.runners_use_private_address
      runners_request_spot_instance     = var.runners_request_spot_instance
      runners_environment_vars          = jsonencode(var.runners_environment_vars)
      runners_pre_build_script          = var.runners_pre_build_script
      runners_post_build_script         = var.runners_post_build_script
      runners_pre_clone_script          = var.runners_pre_clone_script
      runners_request_concurrency       = var.runners_request_concurrency
      runners_output_limit              = var.runners_output_limit
      runners_check_interval            = var.runners_check_interval
      runners_volumes_tmpfs             = join("\n", [for v in var.runners_volumes_tmpfs : format("\"%s\" = \"%s\"", v.volume, v.options)])
      runners_services_volumes_tmpfs    = join("\n", [for v in var.runners_services_volumes_tmpfs : format("\"%s\" = \"%s\"", v.volume, v.options)])
      runners_docker_services           = local.runners_docker_services
      bucket_name                       = local.bucket_name
      shared_cache                      = var.cache_shared
      sentry_dsn                        = var.sentry_dsn
      prometheus_listen_address         = var.prometheus_listen_address
      auth_type                         = var.auth_type_cache_sr
    }
  )
}

data "aws_ami" "docker-machine" {
  count = var.runners_executor == "docker+machine" ? 1 : 0

  most_recent = "true"

  dynamic "filter" {
    for_each = var.runner_ami_filter
    content {
      name   = filter.key
      values = filter.value
    }
  }

  owners = var.runner_ami_owners
}

resource "aws_autoscaling_group" "gitlab_runner_instance" {
  name                      = var.enable_asg_recreation ? "${aws_launch_template.gitlab_runner_instance.name}-asg" : "${var.environment}-as-group"
  vpc_zone_identifier       = length(var.subnet_id) > 0 ? [var.subnet_id] : var.subnet_ids_gitlab_runner
  min_size                  = "1"
  max_size                  = "1"
  desired_capacity          = "1"
  health_check_grace_period = 0
  max_instance_lifetime     = var.asg_max_instance_lifetime
  enabled_metrics           = var.metrics_autoscaling

  dynamic "tag" {
    for_each = local.agent_tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  launch_template {
    id      = aws_launch_template.gitlab_runner_instance.id
    version = aws_launch_template.gitlab_runner_instance.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
    triggers = ["tag"]
  }

  timeouts {
    delete = var.asg_delete_timeout
  }
  lifecycle {
    ignore_changes = [min_size, max_size, desired_capacity]
  }
}

resource "aws_autoscaling_schedule" "scale_in" {
  count                  = var.enable_schedule ? 1 : 0
  autoscaling_group_name = aws_autoscaling_group.gitlab_runner_instance.name
  scheduled_action_name  = "scale_in-${aws_autoscaling_group.gitlab_runner_instance.name}"
  recurrence             = var.schedule_config["scale_in_recurrence"]
  time_zone              = try(var.schedule_config["scale_in_time_zone"], "Etc/UTC")
  min_size               = try(var.schedule_config["scale_in_min_size"], var.schedule_config["scale_in_count"])
  desired_capacity       = try(var.schedule_config["scale_in_desired_capacity"], var.schedule_config["scale_in_count"])
  max_size               = try(var.schedule_config["scale_in_max_size"], var.schedule_config["scale_in_count"])
}

resource "aws_autoscaling_schedule" "scale_out" {
  count                  = var.enable_schedule ? 1 : 0
  autoscaling_group_name = aws_autoscaling_group.gitlab_runner_instance.name
  scheduled_action_name  = "scale_out-${aws_autoscaling_group.gitlab_runner_instance.name}"
  recurrence             = var.schedule_config["scale_out_recurrence"]
  time_zone              = try(var.schedule_config["scale_out_time_zone"], "Etc/UTC")
  min_size               = try(var.schedule_config["scale_out_min_size"], var.schedule_config["scale_out_count"])
  desired_capacity       = try(var.schedule_config["scale_out_desired_capacity"], var.schedule_config["scale_out_count"])
  max_size               = try(var.schedule_config["scale_out_max_size"], var.schedule_config["scale_out_count"])
}

data "aws_ami" "runner" {
  most_recent = "true"

  dynamic "filter" {
    for_each = var.ami_filter
    content {
      name   = filter.key
      values = filter.value
    }
  }

  owners = var.ami_owners
}

resource "aws_launch_template" "gitlab_runner_instance" {
  name_prefix            = local.name_runner_agent_instance
  image_id               = data.aws_ami.runner.id
  user_data              = base64gzip(local.template_user_data)
  instance_type          = var.instance_type
  update_default_version = true
  ebs_optimized          = var.runner_instance_ebs_optimized
  monitoring {
    enabled = var.runner_instance_enable_monitoring
  }
  dynamic "instance_market_options" {
    for_each = var.runner_instance_spot_price == null || var.runner_instance_spot_price == "" ? [] : ["spot"]
    content {
      market_type = instance_market_options.value
      dynamic "spot_options" {
        for_each = var.runner_instance_spot_price == "on-demand-price" ? [] : [0]
        content {
          max_price = var.runner_instance_spot_price
        }
      }
    }
  }
  iam_instance_profile {
    name = local.aws_iam_role_instance_name
  }
  dynamic "block_device_mappings" {
    for_each = [var.runner_root_block_device]
    content {
      device_name = lookup(block_device_mappings.value, "device_name", "/dev/xvda")
      ebs {
        delete_on_termination = lookup(block_device_mappings.value, "delete_on_termination", true)
        volume_type           = lookup(block_device_mappings.value, "volume_type", "gp3")
        volume_size           = lookup(block_device_mappings.value, "volume_size", 8)
        encrypted             = lookup(block_device_mappings.value, "encrypted", true)
        iops                  = lookup(block_device_mappings.value, "iops", null)
        throughput            = lookup(block_device_mappings.value, "throughput", null)
        kms_key_id            = lookup(block_device_mappings.value, "kms_key_id", null)
      }
    }
  }
  network_interfaces {
    security_groups             = concat([aws_security_group.runner.id], var.extra_security_group_ids_runner_agent)
    associate_public_ip_address = false == (var.runner_agent_uses_private_address == false ? var.runner_agent_uses_private_address : var.runners_use_private_address)
  }
  tag_specifications {
    resource_type = "instance"
    tags          = local.tags
  }
  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }
  dynamic "tag_specifications" {
    for_each = var.runner_instance_spot_price == null || var.runner_instance_spot_price == "" ? [] : ["spot"]
    content {
      resource_type = "spot-instances-request"
      tags          = local.tags
    }
  }

  tags = local.tags

  metadata_options {
    http_endpoint               = var.runner_instance_metadata_options.http_endpoint
    http_tokens                 = var.runner_instance_metadata_options.http_tokens
    http_put_response_hop_limit = var.runner_instance_metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = var.runner_instance_metadata_options.instance_metadata_tags
  }

  lifecycle {
    create_before_destroy = true
  }

  # otherwise the agent running on the EC2 instance tries to create the log group
  depends_on = [aws_cloudwatch_log_group.environment]
}

################################################################################
### Create cache bucket
################################################################################
locals {
  bucket_name   = var.cache_bucket["create"] ? module.cache[0].bucket : var.cache_bucket["bucket"]
  bucket_policy = var.cache_bucket["create"] ? module.cache[0].policy_arn : var.cache_bucket["policy"]
}

module "cache" {
  count  = var.cache_bucket["create"] ? 1 : 0
  source = "./modules/cache"

  environment = var.environment
  tags        = local.tags

  cache_bucket_prefix                  = var.cache_bucket_prefix
  cache_bucket_name_include_account_id = var.cache_bucket_name_include_account_id
  cache_bucket_set_random_suffix       = var.cache_bucket_set_random_suffix
  cache_bucket_versioning              = var.cache_bucket_versioning
  cache_expiration_days                = var.cache_expiration_days
  cache_lifecycle_prefix               = var.cache_shared ? "project/" : "runner/"
  cache_logging_bucket                 = var.cache_logging_bucket
  cache_logging_bucket_prefix          = var.cache_logging_bucket_prefix

  kms_key_id = local.kms_key

  name_iam_objects = local.name_iam_objects
}

################################################################################
### Trust policy
################################################################################
resource "aws_iam_instance_profile" "instance" {
  count = var.create_runner_iam_role ? 1 : 0

  name = local.aws_iam_role_instance_name
  role = local.aws_iam_role_instance_name
  tags = local.tags
}

resource "aws_iam_role" "instance" {
  count = var.create_runner_iam_role ? 1 : 0

  name                 = local.aws_iam_role_instance_name
  assume_role_policy   = length(var.instance_role_json) > 0 ? var.instance_role_json : templatefile("${path.module}/policies/instance-role-trust-policy.json", {})
  permissions_boundary = var.permissions_boundary == "" ? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.permissions_boundary}"
  tags                 = merge(local.tags, var.role_tags)
}

################################################################################
### Policies for runner agent instance to create docker machines via spot req.
###
### iam:PassRole To pass the role from the agent to the docker machine runners
################################################################################
resource "aws_iam_policy" "instance_docker_machine_policy" {
  count = var.runners_executor == "docker+machine" && var.create_runner_iam_role ? 1 : 0

  name        = "${local.name_iam_objects}-docker-machine"
  path        = "/"
  description = "Policy for docker machine."
  policy = templatefile("${path.module}/policies/instance-docker-machine-policy.json",
    {
      docker_machine_role_arn = aws_iam_role.docker_machine[0].arn
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "instance_docker_machine_policy" {
  count = var.runners_executor == "docker+machine" && var.create_runner_iam_role ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = aws_iam_policy.instance_docker_machine_policy[0].arn
}

################################################################################
### Policies for runner agent instance to allow connection via Session Manager
################################################################################
resource "aws_iam_policy" "instance_session_manager_policy" {
  count = var.enable_runner_ssm_access ? 1 : 0

  name        = "${local.name_iam_objects}-session-manager"
  path        = "/"
  description = "Policy session manager."
  policy      = templatefile("${path.module}/policies/instance-session-manager-policy.json", {})
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "instance_session_manager_policy" {
  count = var.enable_runner_ssm_access ? 1 : 0

  role       = var.create_runner_iam_role ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = aws_iam_policy.instance_session_manager_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "instance_session_manager_aws_managed" {
  count = var.enable_runner_ssm_access ? 1 : 0

  role       = var.create_runner_iam_role ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

################################################################################
### Add user defined policies
################################################################################
resource "aws_iam_role_policy_attachment" "user_defined_policies" {
  count = length(var.runner_iam_policy_arns)

  role       = var.create_runner_iam_role ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = var.runner_iam_policy_arns[count.index]
}

################################################################################
### Policy for the docker machine instance to access cache
################################################################################
resource "aws_iam_role_policy_attachment" "docker_machine_cache_instance" {
  /* If the S3 cache adapter is configured to use an IAM instance profile, the
     adapter uses the profile attached to the GitLab Runner machine. So do not
     use aws_iam_role.docker_machine.name here! See https://docs.gitlab.com/runner/configuration/advanced-configuration.html */
  count = var.runners_executor == "docker+machine" ? (var.cache_bucket["create"] || lookup(var.cache_bucket, "policy", "") != "" ? 1 : 0) : 0

  role       = var.create_runner_iam_role ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = local.bucket_policy
}

################################################################################
### docker machine instance policy
################################################################################
resource "aws_iam_role" "docker_machine" {
  count                = var.runners_executor == "docker+machine" ? 1 : 0
  name                 = "${local.name_iam_objects}-docker-machine"
  assume_role_policy   = length(var.docker_machine_role_json) > 0 ? var.docker_machine_role_json : templatefile("${path.module}/policies/instance-role-trust-policy.json", {})
  permissions_boundary = var.permissions_boundary == "" ? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.permissions_boundary}"
  tags                 = local.tags
}

resource "aws_iam_instance_profile" "docker_machine" {
  count = var.runners_executor == "docker+machine" ? 1 : 0
  name  = "${local.name_iam_objects}-docker-machine"
  role  = aws_iam_role.docker_machine[0].name
  tags  = local.tags
}

################################################################################
### Add user defined policies
################################################################################
resource "aws_iam_role_policy_attachment" "docker_machine_user_defined_policies" {
  count = var.runners_executor == "docker+machine" ? length(var.docker_machine_iam_policy_arns) : 0

  role       = aws_iam_role.docker_machine[0].name
  policy_arn = var.docker_machine_iam_policy_arns[count.index]
}

################################################################################
resource "aws_iam_role_policy_attachment" "docker_machine_session_manager_aws_managed" {
  count = (var.runners_executor == "docker+machine" && var.enable_docker_machine_ssm_access) ? 1 : 0

  role       = aws_iam_role.docker_machine[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

################################################################################
### Service linked policy, optional
################################################################################
resource "aws_iam_policy" "service_linked_role" {
  count = var.allow_iam_service_linked_role_creation ? 1 : 0

  name        = "${local.name_iam_objects}-service_linked_role"
  path        = "/"
  description = "Policy for creation of service linked roles."
  policy      = templatefile("${path.module}/policies/service-linked-role-create-policy.json", { partition = data.aws_partition.current.partition })
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "service_linked_role" {
  count = var.allow_iam_service_linked_role_creation ? 1 : 0

  role       = var.create_runner_iam_role ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = aws_iam_policy.service_linked_role[0].arn
}

resource "aws_eip" "gitlab_runner" {
  count = var.enable_eip ? 1 : 0
}

################################################################################
### AWS Systems Manager access to store runner token once registered
################################################################################
resource "aws_iam_policy" "ssm" {
  name        = "${local.name_iam_objects}-ssm"
  path        = "/"
  description = "Policy for runner token param access via SSM"
  policy      = templatefile("${path.module}/policies/instance-secure-parameter-role-policy.json", { partition = data.aws_partition.current.partition })
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = var.create_runner_iam_role ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = aws_iam_policy.ssm.arn
}

################################################################################
### AWS assign EIP
################################################################################
resource "aws_iam_policy" "eip" {
  count = var.enable_eip ? 1 : 0

  name        = "${local.name_iam_objects}-eip"
  path        = "/"
  description = "Policy for runner to assign EIP"
  policy      = templatefile("${path.module}/policies/instance-eip.json", {})
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "eip" {
  count = var.enable_eip ? 1 : 0

  role       = var.create_runner_iam_role ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = aws_iam_policy.eip[0].arn
}

################################################################################
### Lambda function triggered as soon as an agent is terminated.
################################################################################
module "terminate_agent_hook" {
  source = "./modules/terminate-agent-hook"

  name                                 = var.asg_terminate_lifecycle_hook_name == null ? "terminate-instances" : var.asg_terminate_lifecycle_hook_name
  environment                          = var.environment
  asg_arn                              = aws_autoscaling_group.gitlab_runner_instance.arn
  asg_name                             = aws_autoscaling_group.gitlab_runner_instance.name
  cloudwatch_logging_retention_in_days = var.cloudwatch_logging_retention_in_days
  name_iam_objects                     = local.name_iam_objects
  name_docker_machine_runners          = local.runner_tags_merged["Name"]
  role_permissions_boundary            = var.permissions_boundary == "" ? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.permissions_boundary}"
  kms_key_id                           = local.kms_key
  arn_format                           = var.arn_format
  tags                                 = local.tags
}
