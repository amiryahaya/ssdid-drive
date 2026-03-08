namespace SsdidDrive.Api.Common;

public readonly struct Result<T>
{
    public T? Value { get; }
    public AppError? Error { get; }
    public bool IsSuccess => Error is null;

    private Result(T value) { Value = value; Error = null; }
    private Result(AppError error) { Value = default; Error = error; }

    public static implicit operator Result<T>(T value) => new(value);
    public static implicit operator Result<T>(AppError error) => new(error);

    public IResult Match(Func<T, IResult> success, Func<AppError, IResult> failure) =>
        IsSuccess ? success(Value!) : failure(Error!);

    public async Task<IResult> Match(Func<T, Task<IResult>> success, Func<AppError, Task<IResult>> failure) =>
        IsSuccess ? await success(Value!) : await failure(Error!);
}
