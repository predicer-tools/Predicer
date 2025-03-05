@testset "Rolling" begin
    roll_data_log = Predicer.roll_predicer(joinpath("..", "input_data", "rolling_model.xlsx"), 24, 6, 0, 48)
    @test haskey(roll_data_log, "model_runs")
    @test haskey(roll_data_log, "runs_info")
    @test haskey(roll_data_log, "meta")
    @test !haskey(roll_data_log, "failed_last_run")
    @test ≈(sum(sum(eachcol(Predicer.collect_cost_dfs(roll_data_log)[!, 3:11]))), 18311.28, atol=0.01)
end
