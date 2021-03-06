#' Knit different versions of a file from chunk and section options
#'
#' \code{versions} is a function that should be included in the setup chunk of
#' an R Markdown document.  Its purpose is to write, then knit, R Markdown source
#' files for several versions of a document, such as different exams in a course.
#'
#'
#' @param pull_solutions Logical - should we create separate solution files for
#' each version of the document?
#' @param to_knit Character vector specifying which versions to write and knit
#' into separate files.  If not specified, all versions are produced.
#'
#' @returns none
#'
#' @details
#'
#' Code chunks may be tagged as version-specific using the option \code{version}.
#' Text sections may also be tagged as version-specific using \code{%%%} wrappers.
#' See example Rmd source below.
#'
#' The version label \code{"solution"} is special if \code{pull_solutions = TRUE},
#' as it is combined with the other version labels to make a solution set.
#'
#' The version label \code{"none"} is special; it will be ignored in the creation
#' of the child documents.  Use it to leave yourself notes in the original document.
#'
#' Example R Markdown source:
#'
#' \preformatted{
#' ---
#' title: "Example"
#' output: html_document
#' ---
#'
#' ```{r, include=FALSE}
#' knitr::opts_chunk$set(echo = TRUE)
#' templar::versions()
#' ```
#'
#' \%\%\%
#' version: A
#'
#' You are taking **Exam A**
#' \%\%\%
#'
#' \%\%\%
#' version: B
#'
#' You are taking **Exam B**
#' \%\%\%
#'
#' ## Question 1: Means
#'
#' Find the mean of the vector `a`
#'
#' ```{r, version = "A"}
#' set.seed(123)
#' ```
#'
#' ```{r, version = "B"}
#' set.seed(456)
#' ```
#'
#' ```{r}
#' a <- rnorm(10)
#' ```
#'
#' \%\%\%
#' version: solution
#'
#' The mean is `r mean(a)`
#' \%\%\%
#'
#' }
#' @export
versions <- function(pull_solutions = TRUE, to_knit = NULL) {

  if (!isTRUE(getOption('knitr.in.progress'))) return()

  orig_file <- knitr::current_input()

  orig_text <- readLines(orig_file)

  # Drop versions() call
  orig_text <- orig_text %>%
    stringr::str_subset("versions\\([^\\)]*\\)", negate = TRUE)

  # Put a warning at the top about editing the sub-files
  top_alert <- c(glue::glue("# Warning:  File created automatically from {orig_file}"),
                 "# Do NOT edit this file directly, as it may be overwritten.")

  end_yaml <- stringr::str_which(orig_text, "---")[2] - 1

  orig_text <- c(orig_text[1:end_yaml], top_alert, orig_text[-c(1:end_yaml)])

  orig_opts <- knitr::opts_current$get()


  # Pull out chunk label info pertaining to versions

  chunk_info <- get_version_chunks(orig_text)
  sec_info <- get_version_text(orig_text)

  all_info <- dplyr::full_join(chunk_info, sec_info) %>%
    dplyr::mutate_all(~tidyr::replace_na(.,FALSE))


  always_col_names <- c("starts", "ends", "is_versioned")


  # In case we only want to knit a few of the versions

  if (!is.null(to_knit)) {

    all_info <- all_info[, c(always_col_names, to_knit)]

  } else {

    to_knit <- setdiff(names(all_info), always_col_names)

  }

  # Do we want to use version = "solution" to create separate solutions?

  if (pull_solutions) {

    to_knit <- setdiff(to_knit, "solution")

    for (v in to_knit) {

      sol_name <- glue::glue("{v}-solution")

      all_info[[sol_name]] <- all_info[[v]] | all_info[["solution"]]

    }

    browser()

    all_info <- all_info %>%
      dplyr::select(-solution)

    to_knit <- setdiff(names(all_info), always_col_names)

  }

  lines_to_delete <- c()

  for (v in to_knit) {

    temp = orig_text

    # Remove sections/chunks from other versions

    delete_me <- all_info$is_versioned & !all_info[,v]

    if (any(delete_me)) {

      lines_to_delete <- all_info[delete_me, c("starts", "ends")] %>%
        purrr::pmap( ~.x:.y) %>%
        unlist()

    }


    # Remove version labels on text sections

    if (nrow(sec_info) > 0) {

      lines_to_delete <- unique(c(lines_to_delete,
                           sec_info$starts,
                           sec_info$starts + 1,
                           sec_info$ends))

    }

    temp = temp[-lines_to_delete]

    # later: remove version options from doc

    new_name <- paste0(stringr::str_remove(orig_file, ".Rmd"),
                       glue::glue("-{v}.Rmd"))

    options(knitr.duplicate.label = 'allow')

    writeLines(temp, new_name)

    rmarkdown::render(new_name, envir = new.env())

  }


  knitr::opts_current$set(orig_opts)

}

#' Gets version tag information from chunks
#' Helper for \code{version()}
#' @importFrom stringr str_which str_subset str_detect str_extract str_extract_all
#' str_split str_trim
get_version_chunks <- function(source_text) {


  chunk_info <- data.frame(

    starts = source_text %>% str_which("```\\{"),
    ends = source_text %>% str_which("```$"),
    is_versioned = source_text %>%
      str_subset("```\\{") %>%
      str_detect("version\\s*=")

  )

  version_opts <- source_text %>%
    str_subset("```\\{") %>%
    str_subset("version\\s*=")

  version_opts_where <- version_opts %>%
    str_extract_all(",\\s*[:alpha:]+\\s*=\\s*") %>%
    purrr::map(~str_which(.x, "version"))

  chunk_versions <- version_opts  %>%
    str_split(",\\s*[:alpha:]+\\s*=\\s*") %>%
    purrr::map2_chr(version_opts_where, ~.x[[.y+1]]) %>%
    purrr::map(~unlist(str_extract_all(.x, '(?<=\\")[:alnum:]+')))

  all_versions <- chunk_versions %>% unlist() %>% unique()


  for (v in all_versions) {

    chunk_info[!chunk_info$is_versioned, v] <- TRUE
    chunk_info[chunk_info$is_versioned, v] <-  purrr::map_lgl(chunk_versions, ~any(str_detect(.x, v)))

  }

  return(chunk_info)

}


#' Gets version tag information from text
#' Helper for \code{version()}
#' @importFrom stringr str_which str_detect str_extract str_split str_trim
get_version_text <- function(source_text) {

  secs <- source_text %>% str_which("%%%")

  if (length(secs) == 0) return(NULL)

  sec_info <- data.frame(
    starts = secs[c(TRUE, FALSE)],
    ends = secs[c(FALSE, TRUE)]
  )

  sec_info$is_versioned = str_detect(source_text[sec_info$starts + 1], "version")

  version_opts <- source_text[sec_info$starts + 1] %>%
    str_extract("(?<=version:).*") %>%
    str_split(",") %>%
    purrr::map(str_trim)

  all_versions <- version_opts %>% unlist() %>% unique()


  for (v in all_versions) {

    sec_info[!sec_info$is_versioned, v] <- TRUE
    sec_info[sec_info$is_versioned, v] <- purrr::map_lgl(version_opts,
                                                         ~any(str_detect(.x, v)))

  }

  return(sec_info)

}



