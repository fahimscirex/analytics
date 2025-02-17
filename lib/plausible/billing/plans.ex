defmodule Plausible.Billing.Plans do
  use Plausible.Repo

  @unlisted_plans_v1 [
    %{limit: 150_000_000, yearly_product_id: "648089", yearly_cost: "$4800"}
  ]

  @unlisted_plans_v2 [
    %{limit: 10_000_000, monthly_product_id: "655350", yearly_cost: "$250"}
  ]

  @sandbox_plans [
    %{
      limit: 10_000,
      monthly_product_id: "19878",
      yearly_product_id: "20127",
      monthly_cost: "$6",
      yearly_cost: "$60"
    },
    %{
      limit: 100_000,
      monthly_product_id: "20657",
      yearly_product_id: "20658",
      monthly_cost: "$12.34",
      yearly_cost: "$120.34"
    }
  ]

  def plans_for(user) do
    case Application.get_env(:plausible, :environment) do
      "dev" ->
        Enum.map(@sandbox_plans, fn plan ->
          Map.put(plan, :volume, number_format(plan[:limit]))
        end)

      _ ->
        real_plans_for(user)
    end
  end

  def real_plans_for(user) do
    user = Repo.preload(user, :subscription)
    v1_plans = plans_v1()

    v1_plan_ids =
      v1_plans
      |> Enum.map(fn plan -> [plan[:monthly_product_id], plan[:yearly_product_id]] end)
      |> List.flatten()

    raw_plans =
      if user.subscription && user.subscription.paddle_plan_id in v1_plan_ids do
        v1_plans
      else
        plans_v2()
      end

    Enum.map(raw_plans, fn plan -> Map.put(plan, :volume, number_format(plan[:limit])) end)
  end

  def all_yearly_plan_ids do
    Enum.map(all_plans(), fn plan -> plan[:yearly_product_id] end)
  end

  def for_product_id(product_id) do
    Enum.find(all_plans(), fn plan ->
      product_id in [plan[:monthly_product_id], plan[:yearly_product_id]]
    end)
  end

  def subscription_interval(%Plausible.Billing.Subscription{paddle_plan_id: "free_10k"}),
    do: "N/A"

  def subscription_interval(subscription) do
    case for_product_id(subscription.paddle_plan_id) do
      nil ->
        enterprise_plan =
          Repo.get_by(Plausible.Billing.EnterprisePlan, user_id: subscription.user_id)

        enterprise_plan && enterprise_plan.billing_interval

      plan ->
        if subscription.paddle_plan_id == plan[:monthly_product_id] do
          "monthly"
        else
          "yearly"
        end
    end
  end

  def allowance(%Plausible.Billing.Subscription{paddle_plan_id: "free_10k"}), do: 10_000

  def allowance(subscription) do
    found = for_product_id(subscription.paddle_plan_id)

    if found do
      Map.fetch!(found, :limit)
    else
      enterprise_plan =
        Repo.get_by(Plausible.Billing.EnterprisePlan, user_id: subscription.user_id)

      enterprise_plan && enterprise_plan.monthly_pageview_limit
    end
  end

  def suggested_plan(user, usage) do
    Enum.find(plans_for(user), fn plan -> usage < plan[:limit] end)
  end

  defp number_format(num) do
    PlausibleWeb.StatsView.large_number_format(num)
  end

  defp all_plans() do
    case Application.get_env(:plausible, :environment) do
      "dev" -> @sandbox_plans
      _ -> plans_v1() ++ @unlisted_plans_v1 ++ plans_v2() ++ @unlisted_plans_v2
    end
  end

  defp plans_v1() do
    File.read!(Application.app_dir(:plausible) <> "/priv/plans_v1.json")
    |> Jason.decode!(keys: :atoms)
  end

  defp plans_v2() do
    File.read!(Application.app_dir(:plausible) <> "/priv/plans_v2.json")
    |> Jason.decode!(keys: :atoms)
  end
end
