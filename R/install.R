#' Install TensorFlow and its dependencies
#'
#' `install_tensorflow()` installs just the tensorflow python package and it's
#' direct dependencies. For a more complete installation that includes
#' additional optional dependencies, use [`keras3::install_keras()`].
#'
#' @details You may be prompted to download and install miniconda if reticulate
#'   did not find a non-system installation of python. Miniconda is the
#'   recommended installation method for most users, as it ensures that the R
#'   python installation is isolated from other python installations. All python
#'   packages will by default be installed into a self-contained conda or venv
#'   environment named "r-reticulate". Note that "conda" is the only supported
#'   method on M1 Mac.
#'
#'   If you initially declined the miniconda installation prompt, you can later
#'   manually install miniconda by running [`reticulate::install_miniconda()`].
#'
#' @section Custom Installation: `install_tensorflow()` or
#'   `keras3::install_keras()` isn't required to use tensorflow with the package.
#'   If you manually configure a python environment with the required
#'   dependencies, you can tell R to use it by pointing reticulate at it,
#'   commonly by setting an environment variable:
#'
#'   ``` R
#'   Sys.setenv("RETICULATE_PYTHON" = "~/path/to/python-env/bin/python")
#'   ```
#'
#' @section Apple Silicon: Beginning with Tensorflow version 2.13, the default
#'   tensorflow package now works on Apple Silicon. See
#'   \url{https://developer.apple.com/metal/tensorflow-plugin/} for instructions
#'   on how to install older versions of Tensorflow on macOS. Please note that
#'   not all operations are supported on Arm Mac GPUs. You can work around the
#'   missing operations by pinning operations to CPU. For example:
#'
#'   ```` R
#'   x <- array(runif(64*64), c(1, 64, 64))
#'   keras3::layer_random_rotation(x, .5)  # Error:
#'   # No registered 'RngReadAndSkip' OpKernel for 'GPU' devices
#'   # Pin the operation to the CPU to avoid the error
#'   with(tf$device("CPU"), keras3::layer_random_rotation(x, .5) ) # No Error
#'   ````
#'
#' @section Additional Packages:
#'
#'   If you wish to add additional PyPI packages to your Keras / TensorFlow
#'   environment you can either specify the packages in the `extra_packages`
#'   argument of `install_tensorflow()` or `install_keras()`, or alternatively
#'   install them into an existing environment using the
#'   [reticulate::py_install()] function. Note that `install_keras()` includes a
#'   set of additional python packages by default, see `?keras3::install_keras`
#'   for details.
#'
#' @md
#'
#' @inheritParams reticulate::py_install
#'
#' @param version TensorFlow version to install. Valid values include:
#'
#'   +  `"default"` installs  `r default_version`
#'
#'   + `"release"` installs the latest release version of tensorflow (which may
#'   be incompatible with the current version of the R package)
#'
#'   + A version specification like `"2.4"` or `"2.4.0"`. Note that if the patch
#'   version is not supplied, the latest patch release is installed (e.g.,
#'   `"2.4"` today installs version "2.4.2")
#'
#'   + `nightly` for the latest available nightly build.
#'
#'   + To any specification, you can append "-cpu" to install the cpu version
#'   only of the package (e.g., `"2.4-cpu"`)
#'
#'   + The full URL or path to a installer binary or python *.whl file.
#'
#' @param extra_packages Additional Python packages to install along with
#'   TensorFlow.
#'
#' @param restart_session Restart R session after installing (note this will
#'   only occur within RStudio).
#'
#' @param python_version,conda_python_version Pass a string like "3.8" to
#'   request that conda install a specific Python version. This is ignored when
#'   attempting to install in a Python virtual environment. Note that the Python
#'   version must be compatible with the requested Tensorflow version,
#'   documented here:
#'   <https://www.tensorflow.org/install/pip#system-requirements>
#'
#' @param cuda logical `TRUE` or `FALSE`. If `install_tensorflow()` detects the platform is
#'   Linux, an Nvidia GPU is available, and the TensorFlow version is 2.14 (the
#'   default), it will install also install the required CUDA libraries through pip.
#'
#' @param metal Whether to install `tensorflow-metal` pip package on Arm Macs.
#'   This enables tensorflow to use the GPU. Pass a string to install a specific
#'   version like `"tensorflow-metal==0.7.*`.
#'
#' @param pip_ignore_installed Whether pip should ignore installed python
#'   packages and reinstall all already installed python packages.
#'
#' @param new_env If `TRUE`, any existing Python virtual environment and/or
#'   conda environment specified by `envname` is deleted first.
#'
#' @param ... other arguments passed to [`reticulate::conda_install()`] or
#'   [`reticulate::virtualenv_install()`], depending on the `method` used.
#'
#' @seealso
#' -  [`keras3::install_keras()`]
#' -  <https://tensorflow.rstudio.com/reference/tensorflow/install_tensorflow>
#'
#' @export
install_tensorflow <-
function(method = c("auto", "virtualenv", "conda"),
         conda = "auto",
         version = "default",
         envname = "r-tensorflow",
         extra_packages = NULL,
         restart_session = TRUE,
         conda_python_version = NULL,
         ...,
         cuda = NULL,
         # tensorflow-metal broken w/ TF v2.16 and default keras:
         # https://github.com/tensorflow/tensorflow/issues/63854#issuecomment-2011725507
         metal = FALSE, #is_mac_arm64(),
         pip_ignore_installed = FALSE,
         new_env = identical(envname, "r-tensorflow"),
         python_version = NULL) {

  method <- match.arg(method)

  # verify 64-bit
  if (.Machine$sizeof.pointer != 8) {
    stop("Unable to install TensorFlow on this platform.",
         "Binary installation is only available for 64-bit platforms.")
  }

  # some special handling for windows
  if (is_windows()) {

    # avoid DLL in use errors
    if (py_available()) {
      stop("You should call install_tensorflow()/install_keras() only in a fresh ",
           "R session that has not yet initialized Keras and TensorFlow (this is ",
           "to avoid DLL in use errors during installation)")
    }

    if(grepl("gpu", as.character(version), ignore.case = TRUE))
      warning("Caution: TensorFlow 2.10 was the last TensorFlow release that supported GPU on native-Windows. Starting with TensorFlow 2.11, you will need to install TensorFlow in WSL2, or install a CPU-only version of TensorFlow.",
              if(identical(.Platform$GUI, "RStudio")) " For a guide on how to use RStudio with WSL2, see https://support.posit.co/hc/en-us/articles/360049776974-Using-RStudio-Server-in-Windows-WSL2")

  }


  can_use_gpu <- FALSE
  if (is.null(cuda)) {

    can_use_gpu <-
      is_linux() &&
      (version %in% c("default", "release") ||
         isTRUE(extract_numeric_version(version) >= "2.14")) &&
      tryCatch(as.logical(length(system("lspci | grep -i nvidia", intern = TRUE))),
               warning = function(w) FALSE) # warning emitted by system for non-0 exit stat

    cuda <- can_use_gpu

  }

  tf_package_spec <- parse_tensorflow_version(version)

  if(isTRUE(cuda) && !grepl("^.*\\.whl$", tf_package_spec)) {
    tf_package_spec <- sub("([^=<>!]*)(.*)", "\\1[and-cuda]\\2",
                           tf_package_spec)
  }

  packages <- unique(c(
    tf_package_spec,
    as.character(extra_packages)
  ))


  if (isTRUE(metal)) repeat {
    tf_ver <- extract_numeric_version(tf_package_spec)
    if(is.na(tf_ver))
      break

    if(tf_ver >= "2.14")
      metal <- "tensorflow-metal>1.0.1"
    else if (tf_ver >= "2.13")
      metal <- "tensorflow-metal>=1.0.1"
    else if (tf_ver >= "2.12")
      metal <- "tensorflow-metal==0.8.*"
    else
      # https://pypi.org/project/tensorflow-metal/
      metal <- "tensorflow-metal"

    break
  }

  python_version <- python_version %||% conda_python_version
  if(method %in% c("auto", "virtualenv") &&
     is.null(python_version)) {

    # virtualenv_starter() picks the most recent version available, but older
    # versions of tensorflow typically don't work with the latest Python
    # release. In general, we're better off picking the oldest Python version available
    # that works with the current release of tensorflow.
    # TF 2.13 is compatible with Python <=3.11,>=3.8

    # prefer 3.10 if we have it, otherwise, find 3.9
    available <- reticulate::virtualenv_starter(version = ">=3.10,<=3.12", all = TRUE)
    if(!nrow(available))
      available <- reticulate::virtualenv_starter(version = ">=3.9,<=3.12", all = TRUE)
    # pick the smallest minor version, ignoring patchlevel
    if(nrow(available)) {
      python_version <- min(available$version[, 1:2])
      ## tf 2.16 supports python 3.12
    #   if(python_version >= "3.12" && isTRUE(grepl("default", version)))
    #     stop(
    #       "The current release version of TensorFlow requires a Python version between 3.9 and 3.11. ",
    #       "Python versions >=3.12 are not supported. Please use ",
    #       "`reticulate::install_python('3.10:latest')` or manually install an older version of Python from www.python.org/downloads"
    #       )
    }
  }

  if (isTRUE(new_env)) {

    if (method %in% c("auto", "virtualenv") &&
        reticulate::virtualenv_exists(envname))
      reticulate::virtualenv_remove(envname = envname, confirm = FALSE)

    if (method %in% c("auto", "conda")) {
      if (!is.null(tryCatch(conda_python(envname, conda = conda),
                            error = function(e) NULL)))
        reticulate::conda_remove(envname, conda = conda)
    }

  }

  py_install_args <- list(
    packages       = packages,
    envname        = envname,
    method         = method,
    conda          = conda,
    python_version = python_version,
    pip            = TRUE,
    pip_ignore_installed = pip_ignore_installed,
    ...
  )

  # now ignored, superseded by `cuda`
  py_install_args$configure_cudnn <- NULL

  do.call(reticulate::py_install, py_install_args)

  if(is_string(metal)) {
    py_install_args$packages <- metal
    tryCatch(do.call(reticulate::py_install, py_install_args),
             error = function(e) {
               message(e)
               message("No suitable version of the 'tensorflow-metal' found. You can ",
                       "use TensorFlow with CPU only, or install a previous release ",
                       "of tensorflow that has GPU support on ARM macs with ",
                       "`tensorflow::install_tensorflow(version = '2.13')`")
             })
  }

  if(cuda && is_linux()) {
    configure_cudnn_symlinks(envname = envname)
    configure_ptxas_symlink(envname = envname)
  }

  cat("\nInstallation complete.\n\n")

  if (restart_session &&
      requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::hasFun("restartSession"))
    rstudioapi::restartSession()

  invisible(NULL)
}

default_version <- numeric_version("2.16")

parse_tensorflow_version <- function(version) {
  # returns unquoted string directly passable to pip, e.g 'tensorflow==2.5.*'

  if(is.null(version) || is.na(version) || version %in% c("", "release"))
    return("tensorflow")

  version <- as.character(version) # if numeric_version()

  if(version == "release-cpu")
    return("tensorflow-cpu")

  # full path to whl.
  if (grepl("^.*\\.whl$", version))
    return(normalizePath(version))

  if (grepl("nightly", version)) {
    if(!startsWith(version, "tf-"))
      version <- paste0("tf-", version)
    return(version)
  }

  package <- "tensorflow"
  if(grepl(".*(cpu|gpu)$", version)) {
    # append {-cpu,-gpu} suffix to package
    package <- sprintf("%s-%s", package, sub(".*-(cpu|gpu)$", "\\1", version))

    # strip -?{cpu,gpu} suffix from version
    version <- sub("(.*?)-?([cg]pu)$", "\\1", version)
  }

  if(version %in% c("default", ""))
    version <- default_version

  if(!grepl("[><=]", version))
    version <- sprintf("==%s.*", version)

  paste0(package, version)
}


extract_numeric_version <- function(x, strict = FALSE) {
  x <- gsub("[^0-9.]+", "", as.character(x), perl = TRUE)
  x <- sub("^\\.+", "", x)
  x <- sub("\\.+$", "", x)
  numeric_version(x, strict = strict)
}


python_module_dir <- function(python, module) {

  force(python)
  py_cmd <- sprintf("import %s; print(%1$s.__file__)", module)

  module_file <- suppressWarnings(system2(
    python, c("-c", shQuote(py_cmd)),
    stdout = TRUE, stderr = TRUE))

  if (!is.null(attr(module_file, "status")) ||
      !is_string(module_file) ||
      !file.exists(module_file))
    return()

  dirname(module_file)

}


configure_cudnn_symlinks <- function(envname) {
  if(!is_linux()) return()
  python <- reticulate::virtualenv_python(envname)

  # For TF 2.13, this assumes that someone already has cudn 11-8 installed,
  # e.g., on ubuntu:
  # sudo apt install cuda-toolkit-11-8
  # also, that `python -m pip install 'nvidia-cudnn-cu11==8.6.*'`

  cudnn_path <- python_module_dir(python, "nvidia.cudnn")
  if(is.null(cudnn_path)) return()
  # "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/nvidia/cudnn"

  cudnn_sos <- Sys.glob(paste0(cudnn_path, "/lib/*.so*"))
  if(!length(cudnn_sos)) return()
  # [1] "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/nvidia/cudnn/lib/libcudnn_adv_infer.so.8"
  # [2] "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/nvidia/cudnn/lib/libcudnn_adv_train.so.8"
  # [3] "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/nvidia/cudnn/lib/libcudnn_cnn_infer.so.8"
  # [4] "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/nvidia/cudnn/lib/libcudnn_cnn_train.so.8"
  # [5] "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/nvidia/cudnn/lib/libcudnn_ops_infer.so.8"
  # [6] "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/nvidia/cudnn/lib/libcudnn_ops_train.so.8"
  # [7] "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/nvidia/cudnn/lib/libcudnn.so.8"

  # "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/tensorflow/__init__.py"
  tf_lib_path <- system2(python, c("-c", shQuote("import tensorflow as tf; print(tf.__file__)")),
                         stderr = FALSE, stdout = TRUE)
  tf_lib_path <- dirname(tf_lib_path)

  from <- sub("^.*/site-packages/", "../", cudnn_sos)
  to <- file.path(tf_lib_path, basename(cudnn_sos))
  writeLines("creating symlinks:")
  writeLines(paste("-", shQuote(to), "->", shQuote(from)))
  # creating symlinks:
  # - '~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/tensorflow/libcudnn_adv_infer.so.8' -> '../nvidia/cudnn/lib/libcudnn_adv_infer.so.8'
  # - '~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/tensorflow/libcudnn_adv_train.so.8' -> '../nvidia/cudnn/lib/libcudnn_adv_train.so.8'
  # - '~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/tensorflow/libcudnn_cnn_infer.so.8' -> '../nvidia/cudnn/lib/libcudnn_cnn_infer.so.8'
  # - '~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/tensorflow/libcudnn_cnn_train.so.8' -> '../nvidia/cudnn/lib/libcudnn_cnn_train.so.8'
  # - '~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/tensorflow/libcudnn_ops_infer.so.8' -> '../nvidia/cudnn/lib/libcudnn_ops_infer.so.8'
  # - '~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/tensorflow/libcudnn_ops_train.so.8' -> '../nvidia/cudnn/lib/libcudnn_ops_train.so.8'
  # - '~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/tensorflow/libcudnn.so.8' -> '../nvidia/cudnn/lib/libcudnn.so.8'
  file.symlink(from = from, to = to)

}

configure_ptxas_symlink <- function(envname = "r-tensorflow") {
  if(!is_linux()) return()
  python <- reticulate::virtualenv_python(envname)

  nvcc_path <- python_module_dir(python, "nvidia.cuda_nvcc")
  if(is.null(nvcc_path)) return()

  # configure a link so that ptxas can be found on the PATH
  # when the venv is activated.
  # https://discuss.tensorflow.org/t/tensorflow-version-2-16-just-released/23140/6#resolving-the-ptxas-issue-3
  nvcc_bins <- Sys.glob(file.path(nvcc_path, "bin/*"))
  if(!length(nvcc_bins)) return()
  # "~/.virtualenvs/r-tensorflow/lib/python3.9/site-packages/nvidia/cuda_nvcc/bin/ptxas"

  to <- file.path(dirname(python), basename(nvcc_bins))
  # "~/.virtualenvs/r-tensorflow/bin/ptxas"

  # fs::path_rel(nvcc_bins, to)
  from <- sub(dirname(dirname(python)), "../..", nvcc_bins)
  # "../../lib/python3.9/site-packages/nvidia/cuda_nvcc/bin/ptxas"

  # writeLines("creating symlinks:")
  writeLines(paste("-", shQuote(to), "->", shQuote(from)))
  # '~/.virtualenvs/r-tensorflow/bin/ptxas' -> '../../lib/python3.9/site-packages/nvidia/cuda_nvcc/bin/ptxas'

  file.symlink(from = from, to = to)

}

