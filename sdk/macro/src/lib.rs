use proc_macro::TokenStream;
use quote::quote;

const WIT_PATH: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../cron.wit");

#[proc_macro_attribute]
pub fn cron_component(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let func = syn::parse_macro_input!(item as syn::ItemFn);
    let func_name = &func.sig.ident;

    if func.sig.asyncness.is_none() {
        return syn::Error::new_spanned(
            func.sig.fn_token,
            "the `#[cron_component]` function must be `async`",
        )
        .to_compile_error()
        .into();
    }

    let preamble = preamble();

    quote!(
        #func
        mod __spin_cron {
            mod preamble {
                #preamble
            }
            impl self::preamble::Guest for preamble::Cron {
                async fn handle_cron_event(metadata: ::spin_cron_sdk::Metadata) -> ::std::result::Result<(), ::spin_cron_sdk::Error> {
                    match super::#func_name(metadata).await {
                        ::std::result::Result::Ok(()) => ::std::result::Result::Ok(()),
                        ::std::result::Result::Err(e) => {
                            eprintln!("{}", e);
                            ::std::result::Result::Err(::spin_cron_sdk::Error::Other(e.to_string()))
                        },
                    }
                }
            }
        }
    ).into()
}

fn preamble() -> proc_macro2::TokenStream {
    let world = "spin-cron";
    quote! {
        #![allow(missing_docs)]
        ::spin_cron_sdk::wit_bindgen::generate!({
            world: #world,
            path: #WIT_PATH,
            runtime_path: "::spin_cron_sdk::wit_bindgen::rt",
            with: {
                "spin:cron/cron-types@3.0.0": ::spin_cron_sdk,
            }
        });
        pub struct Cron;
        export!(Cron);
    }
}
