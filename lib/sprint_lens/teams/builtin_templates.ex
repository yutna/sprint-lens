defmodule SprintLens.Teams.BuiltinTemplates do
  @moduledoc """
  The text the product ships: the five built-in templates FR-201 names, and
  the fallback columns a session gets when it is started without one.

  This module is the canonical list. The seed migration carries its own copy
  on purpose — a migration must not depend on a module that may change shape
  long after it has run everywhere — and the two are kept in step by a test
  that reads the rows back out of the database and compares them to this.

  Why the list exists at all: these strings are the product's own words, not a
  team's, and they have to be translatable (FR-906). A migration is never
  scanned by `mix gettext.extract`, so the canonical list has to live
  somewhere that is. `SprintLensWeb.TemplateText` turns it into one `dgettext`
  call per string, in the `templates` domain, so built-in wording is reviewed
  separately from interface chrome.

  Nothing here translates anything. Which text is the product's and which is a
  team's is a fact about the data; rendering it in a language is a fact about
  the viewer, and that belongs in the web layer.
  """

  @templates [
    {"Start-Stop-Continue",
     [
       {"Start", "What should we begin doing?"},
       {"Stop", "What should we stop doing?"},
       {"Continue", "What is working and should carry on?"}
     ]},
    {"Mad-Sad-Glad",
     [
       {"Mad", "What frustrated you?"},
       {"Sad", "What disappointed you?"},
       {"Glad", "What made you happy?"}
     ]},
    {"4Ls",
     [
       {"Liked", "What did you enjoy?"},
       {"Learned", "What did you find out?"},
       {"Lacked", "What was missing?"},
       {"Longed for", "What did you wish you had?"}
     ]},
    {"KPT",
     [
       {"Keep", "What is worth keeping?"},
       {"Problem", "What got in the way?"},
       {"Try", "What should we try next?"}
     ]},
    {"Sailboat",
     [
       {"Wind", "What is pushing us forward?"},
       {"Anchor", "What is holding us back?"},
       {"Rocks", "What risks are ahead?"},
       {"Island", "What are we aiming for?"}
     ]}
  ]

  # A session with no template still gets a board: an empty one would leave
  # participants with nowhere to write (FR-917). These are the product's
  # words too, so they are translated on the same terms.
  @fallback_columns [
    %{"name" => "Went well", "hint" => nil},
    %{"name" => "To improve", "hint" => nil},
    %{"name" => "Actions", "hint" => nil}
  ]

  @strings (Enum.flat_map(@templates, fn {name, columns} ->
              [name | Enum.flat_map(columns, fn {column, hint} -> [column, hint] end)]
            end) ++ Enum.map(@fallback_columns, & &1["name"]))
           |> Enum.uniq()

  @doc """
  The five built-in templates, as `{name, [{column_name, hint}]}`.
  """
  @spec all() :: [{String.t(), [{String.t(), String.t()}]}]
  def all, do: @templates

  @doc """
  The columns a session gets when it is started from no template at all.
  """
  @spec fallback_columns() :: [map()]
  def fallback_columns, do: @fallback_columns

  @doc """
  Every distinct string the product ships in a template or a fallback column.

  This is the list `SprintLensWeb.TemplateText` generates its clauses from,
  and the list its test walks to prove none of them was missed.
  """
  @spec strings() :: [String.t()]
  def strings, do: @strings
end
